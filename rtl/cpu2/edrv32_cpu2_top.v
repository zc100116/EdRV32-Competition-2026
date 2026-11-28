// File: edrv32_cpu2_top.v
// Spec: cpu-v2-spec 1, 3; interface-freeze decisions and implementation supplements.
// Description: Integer core, ordered retirement and L1 integration for NONE.
// Clock domain: clk_sys.
module edrv32_cpu2_top #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    input wire clk_i,
    input wire rst_n_i,
    output wire [3:0] ic_axi_arid_o,
    output wire [31:0] ic_axi_araddr_o,
    output wire [7:0] ic_axi_arlen_o,
    output wire [2:0] ic_axi_arsize_o,
    output wire [1:0] ic_axi_arburst_o,
    output wire ic_axi_arvalid_o,
    input wire ic_axi_arready_i,
    input wire [3:0] ic_axi_rid_i,
    input wire [63:0] ic_axi_rdata_i,
    input wire [1:0] ic_axi_rresp_i,
    input wire ic_axi_rlast_i,
    input wire ic_axi_rvalid_i,
    output wire ic_axi_rready_o,
    output wire [3:0] dc_axi_arid_o,
    output wire [31:0] dc_axi_araddr_o,
    output wire [7:0] dc_axi_arlen_o,
    output wire [2:0] dc_axi_arsize_o,
    output wire [1:0] dc_axi_arburst_o,
    output wire dc_axi_arvalid_o,
    input wire dc_axi_arready_i,
    input wire [3:0] dc_axi_rid_i,
    input wire [63:0] dc_axi_rdata_i,
    input wire [1:0] dc_axi_rresp_i,
    input wire dc_axi_rlast_i,
    input wire dc_axi_rvalid_i,
    output wire dc_axi_rready_o,
    output wire [3:0] dc_axi_awid_o,
    output wire [31:0] dc_axi_awaddr_o,
    output wire [7:0] dc_axi_awlen_o,
    output wire [2:0] dc_axi_awsize_o,
    output wire [1:0] dc_axi_awburst_o,
    output wire dc_axi_awvalid_o,
    input wire dc_axi_awready_i,
    output wire [63:0] dc_axi_wdata_o,
    output wire [7:0] dc_axi_wstrb_o,
    output wire dc_axi_wlast_o,
    output wire dc_axi_wvalid_o,
    input wire dc_axi_wready_i,
    input wire [3:0] dc_axi_bid_i,
    input wire [1:0] dc_axi_bresp_i,
    input wire dc_axi_bvalid_i,
    output wire dc_axi_bready_o,
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,
    output wire cache_irq_o,
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i,
    output wire [63:0] debug_o
);
    // CLAUDE 5.2: three regional copies release together after one destination edge.
    wire rst_frontend_n_w;
    edrv32_reset_copy u_reset_frontend (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_frontend_n_w)
    );
    wire rst_execute_n_w;
    edrv32_reset_copy u_reset_execute (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_execute_n_w)
    );
    wire rst_commit_cache_n_w;
    edrv32_reset_copy u_reset_commit_cache (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_commit_cache_n_w)
    );
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam RAS_DATA = ISSUE_WIDTH == 2 ? 256 : 128;
    localparam RAS_PTR = ISSUE_WIDTH == 2 ? 3 : 2;
    localparam RAS_COUNT = ISSUE_WIDTH == 2 ? 4 : 3;
    wire [$clog2((ISSUE_WIDTH == 2 ? 8 : 4)+5)-1:0] ib_count_w;
    wire [1:0] frontend_active_w;
    wire frontend_flush_w;
    wire redirect_valid_w;
    wire [32-1:0] redirect_pc_w;
    wire branch_redirect_valid_w;
    wire [T-1:0] branch_redirect_tag_w;
    wire [32-1:0] branch_redirect_pc_w;
    wire commit_redirect_valid_w;
    wire [32-1:0] commit_redirect_pc_w;
    wire fetch_stop_w;
    wire [RAS_DATA-1:0] branch_redirect_ras_data_w;
    wire [RAS_PTR-1:0] branch_redirect_ras_ptr_w;
    wire [RAS_COUNT-1:0] branch_redirect_ras_count_w;
    wire branch_redirect_ras_pop_w;
    wire branch_redirect_ras_push_w;
    wire [32-1:0] branch_redirect_link_w;
    wire [2-1:0] ib_remove_count_w;
    wire [4-1:0] ib_credit_w;
    wire [31:1] lvt_w;
    wire wb0_valid_w;
    wire [5-1:0] wb0_rd_w;
    wire wb1_valid_w;
    wire [5-1:0] wb1_rd_w;
    wire wb0_valid_copy_w;
    wire [4:0] wb0_rd_copy_w;
    wire wb1_valid_copy_w;
    wire [4:0] wb1_rd_copy_w;
    wire ib_head0_valid_w;
    wire ib_head1_valid_w;
    wire [32-1:0] ib_head0_pc_w;
    wire [32-1:0] ib_head0_instr_w;
    wire ib_head0_error_w;
    wire [5-1:0] ib_head0_candidates_w;
    wire ib_head0_predict_taken_w;
    wire [32-1:0] ib_head0_predict_target_w;
    wire ib_head0_predict_token_w;
    wire [3-1:0] ib_head0_predict_provider_w;
    wire ib_head0_predict_alternate_w;
    wire [9-1:0] ib_head0_predict_index0_w;
    wire [9-1:0] ib_head0_predict_index1_w;
    wire [9-1:0] ib_head0_predict_index2_w;
    wire [9-1:0] ib_head0_predict_index3_w;
    wire [10-1:0] ib_head0_predict_tag0_w;
    wire [10-1:0] ib_head0_predict_tag1_w;
    wire [10-1:0] ib_head0_predict_tag2_w;
    wire [10-1:0] ib_head0_predict_tag3_w;
    wire [12-1:0] ib_head0_predict_base_index_w;
    wire [12-1:0] ib_head0_predict_fast_index_w;
    wire [RAS_DATA-1:0] ib_head0_ras_data_w;
    wire [RAS_PTR-1:0] ib_head0_ras_ptr_w;
    wire [RAS_COUNT-1:0] ib_head0_ras_count_w;
    wire [32-1:0] ib_head1_pc_w;
    wire [32-1:0] ib_head1_instr_w;
    wire ib_head1_error_w;
    wire [5-1:0] ib_head1_candidates_w;
    wire ib_head1_predict_taken_w;
    wire [32-1:0] ib_head1_predict_target_w;
    wire ib_head1_predict_token_w;
    wire [3-1:0] ib_head1_predict_provider_w;
    wire ib_head1_predict_alternate_w;
    wire [9-1:0] ib_head1_predict_index0_w;
    wire [9-1:0] ib_head1_predict_index1_w;
    wire [9-1:0] ib_head1_predict_index2_w;
    wire [9-1:0] ib_head1_predict_index3_w;
    wire [10-1:0] ib_head1_predict_tag0_w;
    wire [10-1:0] ib_head1_predict_tag1_w;
    wire [10-1:0] ib_head1_predict_tag2_w;
    wire [10-1:0] ib_head1_predict_tag3_w;
    wire [12-1:0] ib_head1_predict_base_index_w;
    wire [12-1:0] ib_head1_predict_fast_index_w;
    wire [RAS_DATA-1:0] ib_head1_ras_data_w;
    wire [RAS_PTR-1:0] ib_head1_ras_ptr_w;
    wire [RAS_COUNT-1:0] ib_head1_ras_count_w;
    wire ic_req_valid_w;
    wire ic_req_ready_w;
    wire [32-1:0] ic_req_addr_w;
    wire ic_resp_valid_w;
    wire ic_resp_ready_w;
    wire ic_cancel_w;
    wire f2_redirect_valid_w;
    wire [31:0] f2_redirect_pc_w;
    wire [31:0] f2_redirect_target_w;
    wire [1:0] f2_redirect_cause_w;
    wire [32-1:0] ic_resp_bank0_way0_instr_w;
    wire [32-1:0] ic_resp_bank0_way1_instr_w;
    wire [32-1:0] ic_resp_bank1_way0_instr_w;
    wire [32-1:0] ic_resp_bank1_way1_instr_w;
    wire [2-1:0] ic_resp_bank0_way_hit_w;
    wire ic_resp_bank0_error_w;
    wire [2-1:0] ic_resp_bank1_way_hit_w;
    wire ic_resp_bank1_error_w;
    wire predict_read0_valid_w;
    wire [T-1:0] predict_read0_tag_w;
    wire [9-1:0] predict_read0_index0_w;
    wire [9-1:0] predict_read0_index1_w;
    wire [9-1:0] predict_read0_index2_w;
    wire [9-1:0] predict_read0_index3_w;
    wire [10-1:0] predict_read0_tag0_w;
    wire [10-1:0] predict_read0_tag1_w;
    wire [10-1:0] predict_read0_tag2_w;
    wire [10-1:0] predict_read0_tag3_w;
    wire [12-1:0] predict_read0_base_index_w;
    wire predict_read1_valid_w;
    wire [T-1:0] predict_read1_tag_w;
    wire [9-1:0] predict_read1_index0_w;
    wire [9-1:0] predict_read1_index1_w;
    wire [9-1:0] predict_read1_index2_w;
    wire [9-1:0] predict_read1_index3_w;
    wire [10-1:0] predict_read1_tag0_w;
    wire [10-1:0] predict_read1_tag1_w;
    wire [10-1:0] predict_read1_tag2_w;
    wire [10-1:0] predict_read1_tag3_w;
    wire [12-1:0] predict_read1_base_index_w;
    wire ex_predict_train_valid_w;
    wire [T-1:0] ex_predict_train_tag_w;
    wire [32-1:0] ex_predict_train_pc_w;
    wire ex_predict_train_taken_w;
    wire [32-1:0] ex_predict_train_target_w;
    wire [3-1:0] ex_predict_train_type_w;
    wire [12-1:0] ex_predict_train_fast_index_w;
    wire ex_predict_train_token_w;
    wire [3-1:0] ex_predict_train_provider_w;
    wire ex_predict_train_prediction_w;
    wire ex_predict_train_alternate_w;
    wire [9-1:0] ex_predict_train_index0_w;
    wire [9-1:0] ex_predict_train_index1_w;
    wire [9-1:0] ex_predict_train_index2_w;
    wire [9-1:0] ex_predict_train_index3_w;
    wire [10-1:0] ex_predict_train_tag0_w;
    wire [10-1:0] ex_predict_train_tag1_w;
    wire [10-1:0] ex_predict_train_tag2_w;
    wire [10-1:0] ex_predict_train_tag3_w;
    wire [12-1:0] ex_predict_train_base_index_w;
    wire mem_predict_train_valid_w;
    wire [T-1:0] mem_predict_train_tag_w;
    wire [32-1:0] mem_predict_train_pc_w;
    wire mem_predict_train_taken_w;
    wire [32-1:0] mem_predict_train_target_w;
    wire [3-1:0] mem_predict_train_type_w;
    wire [12-1:0] mem_predict_train_fast_index_w;
    wire mem_predict_train_token_w;
    wire [3-1:0] mem_predict_train_provider_w;
    wire mem_predict_train_prediction_w;
    wire mem_predict_train_alternate_w;
    wire [9-1:0] mem_predict_train_index0_w;
    wire [9-1:0] mem_predict_train_index1_w;
    wire [9-1:0] mem_predict_train_index2_w;
    wire [9-1:0] mem_predict_train_index3_w;
    wire [10-1:0] mem_predict_train_tag0_w;
    wire [10-1:0] mem_predict_train_tag1_w;
    wire [10-1:0] mem_predict_train_tag2_w;
    wire [10-1:0] mem_predict_train_tag3_w;
    wire [12-1:0] mem_predict_train_base_index_w;
    wire [T-1:0] age_head_w;
    wire cancel_valid_w;
    wire [T-1:0] cancel_tag_w;
    wire alu0_complete_valid_w;
    wire alu0_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] alu0_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_w;
    wire alu1_complete_valid_w;
    wire alu1_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] alu1_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_w;
    wire branch_complete_valid_w;
    wire branch_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] branch_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_w;
    wire mul_complete_valid_w;
    wire mul_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] mul_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] mul_complete_data_w;
    wire div_complete_valid_w;
    wire div_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] div_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] div_complete_data_w;
    wire lsu_complete_valid_w;
    wire lsu_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] lsu_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_complete_data_w;
    wire csr_complete_valid_w;
    wire csr_complete_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] csr_complete_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] csr_complete_data_w;
    wire fp_resp_valid_w;
    wire fp_resp_ready_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] fp_resp_tag_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_resp_data_w;
    wire lsu_complete_device_w;
    wire [2-1:0] csr_fs_w;
    wire [3-1:0] csr_frm_w;
    wire [5-1:0] id_rs0_w;
    wire id_owner0_w;
    wire [32-1:0] id_data0_w;
    wire [5-1:0] id_rs1_w;
    wire id_owner1_w;
    wire [32-1:0] id_data1_w;
    wire [5-1:0] id_rs2_w;
    wire id_owner2_w;
    wire [32-1:0] id_data2_w;
    wire [5-1:0] id_rs3_w;
    wire id_owner3_w;
    wire [32-1:0] id_data3_w;
    wire [32-1:0] wb0_data_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] wb0_tag_w;
    wire [32-1:0] wb1_data_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] wb1_tag_w;
    wire [5-1:0] fp_read0_addr_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read0_data_w;
    wire [5-1:0] fp_read1_addr_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read1_data_w;
    wire [5-1:0] fp_read2_addr_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read2_data_w;
    wire fp_wb_valid_w;
    wire [5-1:0] fp_wb_rd_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_wb_data_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] fp_wb_tag_w;
    wire [(FPU_FORMAT>"FD"?3:FPU_FORMAT>"F"?5:4)-1:0] allocate_credit_w;
    wire allocate_ready_w;
    wire allocate_valid_w;
    wire [2-1:0] allocate_count_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] allocate0_tag_w;
    wire [32-1:0] allocate0_pc_w;
    wire [32-1:0] allocate0_instr_w;
    wire [5-1:0] allocate0_rd_w;
    wire [2-1:0] allocate0_dest_w;
    wire [32-1:0] allocate0_csr_src_w;
    wire allocate0_store_w;
    wire allocate0_divide_w;
    wire allocate0_double_beat_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] allocate1_tag_w;
    wire [32-1:0] allocate1_pc_w;
    wire [32-1:0] allocate1_instr_w;
    wire [5-1:0] allocate1_rd_w;
    wire [2-1:0] allocate1_dest_w;
    wire [32-1:0] allocate1_csr_src_w;
    wire allocate1_store_w;
    wire allocate1_divide_w;
    wire allocate1_double_beat_w;
    wire source0_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] source0_tag_w;
    wire source0_domain_w;
    wire source0_ready_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source0_data_w;
    wire source1_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] source1_tag_w;
    wire source1_domain_w;
    wire source1_ready_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source1_data_w;
    wire source2_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] source2_tag_w;
    wire source2_domain_w;
    wire source2_ready_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source2_data_w;
    wire source3_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] source3_tag_w;
    wire source3_domain_w;
    wire source3_ready_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source3_data_w;
    wire source4_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] source4_tag_w;
    wire source4_domain_w;
    wire source4_ready_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source4_data_w;
    wire execute0_ready_w;
    wire execute0_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute0_tag_w;
    wire [32-1:0] execute0_pc_w;
    wire [32-1:0] execute0_instr_w;
    wire [32-1:0] execute0_src1_w;
    wire [32-1:0] execute0_src2_w;
    wire [32-1:0] execute0_imm_w;
    wire execute0_late_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute0_source1_tag_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute0_source2_tag_w;
    wire execute0_source1_wait_w;
    wire execute0_source2_wait_w;
    wire execute0_predict_taken_w;
    wire [32-1:0] execute0_predict_target_w;
    wire execute0_predict_token_w;
    wire [3-1:0] execute0_predict_provider_w;
    wire execute0_predict_alternate_w;
    wire [9-1:0] execute0_predict_index0_w;
    wire [9-1:0] execute0_predict_index1_w;
    wire [9-1:0] execute0_predict_index2_w;
    wire [9-1:0] execute0_predict_index3_w;
    wire [10-1:0] execute0_predict_tag0_w;
    wire [10-1:0] execute0_predict_tag1_w;
    wire [10-1:0] execute0_predict_tag2_w;
    wire [10-1:0] execute0_predict_tag3_w;
    wire [12-1:0] execute0_predict_base_index_w;
    wire [12-1:0] execute0_predict_fast_index_w;
    wire [(128*ISSUE_WIDTH)-1:0] execute0_ras_data_w;
    wire [(ISSUE_WIDTH+1)-1:0] execute0_ras_ptr_w;
    wire [(ISSUE_WIDTH+2)-1:0] execute0_ras_count_w;
    wire execute1_ready_w;
    wire execute1_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute1_tag_w;
    wire [32-1:0] execute1_pc_w;
    wire [32-1:0] execute1_instr_w;
    wire [32-1:0] execute1_src1_w;
    wire [32-1:0] execute1_src2_w;
    wire [32-1:0] execute1_imm_w;
    wire execute1_late_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute1_source1_tag_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute1_source2_tag_w;
    wire execute1_source1_wait_w;
    wire execute1_source2_wait_w;
    wire execute1_predict_taken_w;
    wire [32-1:0] execute1_predict_target_w;
    wire execute1_predict_token_w;
    wire [3-1:0] execute1_predict_provider_w;
    wire execute1_predict_alternate_w;
    wire [9-1:0] execute1_predict_index0_w;
    wire [9-1:0] execute1_predict_index1_w;
    wire [9-1:0] execute1_predict_index2_w;
    wire [9-1:0] execute1_predict_index3_w;
    wire [10-1:0] execute1_predict_tag0_w;
    wire [10-1:0] execute1_predict_tag1_w;
    wire [10-1:0] execute1_predict_tag2_w;
    wire [10-1:0] execute1_predict_tag3_w;
    wire [12-1:0] execute1_predict_base_index_w;
    wire [12-1:0] execute1_predict_fast_index_w;
    wire [(128*ISSUE_WIDTH)-1:0] execute1_ras_data_w;
    wire [(ISSUE_WIDTH+1)-1:0] execute1_ras_ptr_w;
    wire [(ISSUE_WIDTH+2)-1:0] execute1_ras_count_w;
    wire mul_req_ready_w;
    wire mul_req_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] mul_req_tag_w;
    wire [32-1:0] mul_req_instr_w;
    wire [32-1:0] mul_req_src1_w;
    wire [32-1:0] mul_req_src2_w;
    wire div_req_ready_w;
    wire div_req_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] div_req_tag_w;
    wire [32-1:0] div_req_instr_w;
    wire [32-1:0] div_req_src1_w;
    wire [32-1:0] div_req_src2_w;
    wire lsu_req_ready_w;
    wire lsu_req_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] lsu_req_tag_w;
    wire [32-1:0] lsu_req_instr_w;
    wire [32-1:0] lsu_req_addr_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_req_store_data_w;
    wire lsu_req_early_w;
    wire csr_req_ready_w;
    wire csr_req_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] csr_req_tag_w;
    wire [32-1:0] csr_req_instr_w;
    wire [32-1:0] csr_req_src_w;
    wire fp_req_ready_w;
    wire fp_req_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] fp_req_tag_w;
    wire [32-1:0] fp_req_instr_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src1_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src2_w;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src3_w;
    wire [32-1:0] fp_req_int_src_w;
    wire [3-1:0] fp_req_rm_w;
    wire early_req_valid_w;
    wire [32-1:0] early_req_addr_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] early_req_tag_w;
    wire decode_complete_ready_w;
    wire decode_complete_valid_w;
    wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] decode_complete_tag_w;
    wire decode_complete_exception_w;
    wire [4-1:0] decode_complete_cause_w;
    wire [32-1:0] decode_complete_tval_w;
    wire [7:0] issue_hpm_w;
    wire [2:0] issue_pair_cause_w;
    wire issue_wait_w;
    wire alu_execute0_valid_w;
    wire alu_execute0_ready_w;
    wire alu_execute1_valid_w;
    wire alu_execute1_ready_w;
    wire [5-1:0] alu0_complete_flags_w;
    wire alu0_complete_exception_w;
    wire [4-1:0] alu0_complete_cause_w;
    wire [32-1:0] alu0_complete_tval_w;
    wire [5-1:0] alu1_complete_flags_w;
    wire alu1_complete_exception_w;
    wire [4-1:0] alu1_complete_cause_w;
    wire [32-1:0] alu1_complete_tval_w;
    wire [1:0] alu_debug_mem_valid_w;
    wire branch_execute0_valid_w;
    wire branch_execute0_ready_w;
    wire branch_execute1_valid_w;
    wire branch_execute1_ready_w;
    wire [5-1:0] branch_complete_flags_w;
    wire branch_complete_exception_w;
    wire [4-1:0] branch_complete_cause_w;
    wire [32-1:0] branch_complete_tval_w;
    wire [32-1:0] branch_complete_next_pc_w;
    wire [31:0] trace_branch_pc_w;
    wire [1:0] trace_branch_stage_w;
    wire [1:0] trace_branch_cause_w;
    wire [1:0] branch_debug_mem_valid_w;
    wire [4:0] mul_complete_flags_w;
    wire mul_complete_exception_w;
    wire [3:0] mul_complete_cause_w;
    wire [31:0] mul_complete_tval_w;
    wire [4:0] div_complete_flags_w;
    wire div_complete_exception_w;
    wire [3:0] div_complete_cause_w;
    wire [31:0] div_complete_tval_w;
    wire [1:0] retire_count_w;
    wire commit_cancel_valid_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_cancel_tag_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head0_tag_w;
    wire [31:0] head0_pc_w;
    wire [31:0] head0_next_pc_w;
    wire [3:0] head0_kind_w;
    wire [31:0] head0_trace_instr_w;
    wire [4:0] head0_rd_w;
    wire [1:0] head0_dest_w;
    wire head0_store_w;
    wire head0_divide_w;
    wire head0_double_beat_w;
    wire head0_valid_w;
    wire head0_done_w;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head0_data_w;
    wire [4:0] head0_flags_w;
    wire head0_exception_w;
    wire [3:0] head0_cause_w;
    wire [31:0] head0_tval_w;
    wire head0_device_w;
    wire [31:0] head0_mem_addr_w;
    wire [63:0] head0_mem_data_w;
    wire [7:0] head0_mem_mask_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head1_tag_w;
    wire [31:0] head1_pc_w;
    wire [31:0] head1_next_pc_w;
    wire [3:0] head1_kind_w;
    wire [31:0] head1_trace_instr_w;
    wire [4:0] head1_rd_w;
    wire [1:0] head1_dest_w;
    wire head1_store_w;
    wire head1_divide_w;
    wire head1_double_beat_w;
    wire head1_valid_w;
    wire head1_done_w;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head1_data_w;
    wire [4:0] head1_flags_w;
    wire head1_exception_w;
    wire [3:0] head1_cause_w;
    wire [31:0] head1_tval_w;
    wire head1_device_w;
    wire [31:0] head1_mem_addr_w;
    wire [63:0] head1_mem_data_w;
    wire [7:0] head1_mem_mask_w;
    wire [4:0] lsu_complete_flags_w;
    wire lsu_complete_exception_w;
    wire [3:0] lsu_complete_cause_w;
    wire [31:0] lsu_complete_tval_w;
    wire [4:0] csr_complete_flags_w;
    wire csr_complete_exception_w;
    wire [3:0] csr_complete_cause_w;
    wire [31:0] csr_complete_tval_w;
    wire [4:0] fp_resp_flags_w;
    wire fp_resp_int_dest_w;
    wire [31:0] lsu_complete_mem_addr_w;
    wire [63:0] lsu_complete_mem_data_w;
    wire [7:0] lsu_complete_mem_mask_w;
    wire commit_lsu_valid_w;
    wire commit_lsu_ready_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_tag_w;
    wire commit_lsu_done_valid_w;
    wire commit_lsu_done_ready_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_done_tag_w;
    wire commit_lsu_done_error_w;
    wire [31:0] commit_lsu_done_fault_addr_w;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] commit_lsu_done_data_w;
    wire csr_commit_valid_w;
    wire fp_commit_flags_valid_w;
    wire [4:0] fp_commit_flags_w;
    wire fp_commit_write_w;
    wire irq_pending_w;
    wire [31:0] irq_cause_w;
    wire irq_wake_w;
    wire [31:0] trap_target_w;
    wire [31:0] csr_mepc_w;
    wire mret_valid_w;
    wire trap_valid_w;
    wire [31:0] trap_pc_w;
    wire [31:0] trap_cause_w;
    wire [31:0] trap_tval_w;
    wire dc_fence_valid_w;
    wire dc_fence_ready_w;
    wire dc_fence_clean_all_w;
    wire dc_fence_done_w;
    wire ic_inv_valid_w;
    wire ic_inv_ready_w;
    wire ic_inv_done_w;
    wire [1:0] counter_retire_count_w;
    wire [1:0] hpm_branch_count_w;
    wire [1:0] trace_valid_w;
    wire [63:0] trace_pc_w;
    wire [63:0] trace_instr_w;
    wire [9:0] trace_rd_w;
    wire [3:0] trace_rd_domain_w;
    wire [127:0] trace_rd_data_w;
    wire [9:0] trace_flags_w;
    wire [1:0] trace_mem_valid_w;
    wire [1:0] trace_mem_store_w;
    wire [63:0] trace_mem_addr_w;
    wire [127:0] trace_mem_data_w;
    wire [15:0] trace_mem_mask_w;
    wire trace_trap_w;
    wire [31:0] trace_cause_w;
    wire [31:0] trace_trap_pc_w;
    wire [31:0] trace_tval_w;
    wire commit_mem_wait_w;
    wire commit_div_wait_w;
    wire commit_device_wait_w;
    wire [15:0] hpm_event_w;
    wire [1:0] trace_csr_valid_w;
    wire [23:0] trace_csr_addr_w;
    wire [63:0] trace_csr_data_w;
    wire [4:0] trace_fflags_w;
    wire [2:0] trace_frm_w;
    wire [1:0] trace_fs_w;
    wire early_resp_valid_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] early_resp_tag_w;
    wire early_resp_hit_w;
    wire [31:0] early_resp_data_w;
    wire dc_req_valid_w;
    wire dc_req_ready_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_req_tag_w;
    wire dc_req_beat_w;
    wire [31:0] dc_req_addr_w;
    wire dc_req_store_w;
    wire [1:0] dc_req_size_w;
    wire [31:0] dc_req_data_w;
    wire [3:0] dc_req_mask_w;
    wire dc_req_early_w;
    wire dc_resp_valid_w;
    wire dc_resp_ready_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_resp_tag_w;
    wire dc_resp_beat_w;
    wire [1:0] dc_resp_way_hit_w;
    wire [31:0] dc_resp_way0_data_w;
    wire [31:0] dc_resp_way1_data_w;
    wire dc_resp_error_w;
    wire dc_resp_device_w;
    wire dc_commit_valid_w;
    wire dc_commit_ready_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_commit_tag_w;
    wire dc_commit_beat_w;
    wire [31:0] dc_commit_data_w;
    wire [3:0] dc_commit_mask_w;
    wire dc_done_valid_w;
    wire dc_done_ready_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_done_tag_w;
    wire dc_done_beat_w;
    wire dc_done_error_w;
    wire [31:0] dc_done_data_w;
    wire dc_early_valid_w;
    wire [31:0] dc_early_addr_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_early_tag_w;
    wire dc_early_resp_valid_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_early_resp_tag_w;
    wire [1:0] dc_early_hit_w;
    wire [31:0] dc_early_way0_data_w;
    wire [31:0] dc_early_way1_data_w;
    wire dc_cancel_valid_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_cancel_tag_w;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_age_head_w;
    wire ic_miss_event_w;
    wire icache_debug_miss_w;
    wire maint_req_valid_w;
    wire maint_req_ready_w;
    wire [2:0] maint_cmd_w;
    wire [31:0] maint_addr_w;
    wire [31:0] maint_size_w;
    wire maint_busy_w;
    wire wb_err_w;
    wire [31:0] wb_err_addr_w;
    wire dc_wb_event_w;
    wire dc_miss_event_w;
    wire trace_mem_effect_valid_w;
    wire [(FPU_FORMAT=="FD" ? 4 : FPU_FORMAT=="F" ? 3 : 2)-1:0] trace_mem_effect_tag_w;
    wire [31:0] trace_mem_effect_addr_w;
    wire [31:0] trace_mem_effect_data_w;
    wire [3:0] trace_mem_effect_mask_w;
    wire dcache_debug_miss_w;
    wire execute0_branch_w;
    wire execute1_branch_w;
    assign fp_resp_valid_w = 1'b0;
    assign fp_resp_tag_w = 'd0;
    assign fp_resp_data_w = 'd0;
    assign fp_read0_data_w = 'd0;
    assign fp_read1_data_w = 'd0;
    assign fp_read2_data_w = 'd0;
    assign fp_req_ready_w = 1'b0;
    assign fp_resp_flags_w = 'd0;
    assign fp_resp_int_dest_w = 1'b0;
    assign frontend_flush_w = 1'b0;
    assign redirect_valid_w = 1'b0;
    assign redirect_pc_w = 32'b0;
    assign hpm_event_w = {
        branch_redirect_valid_w,
        dc_wb_event_w, dc_miss_event_w, ic_miss_event_w,
        issue_hpm_w[7], issue_hpm_w[6] || commit_device_wait_w,
        issue_hpm_w[5] || commit_div_wait_w, issue_hpm_w[4],
        issue_hpm_w[3:0], 1'b0,
        retire_count_w == 2'd0, retire_count_w == 2'd1, retire_count_w == 2'd2};
    // C04 observation, retirement fields are in program order.
    wire [2:0] debug_ib_count_w;
    assign debug_ib_count_w = ib_count_w > 7 ? 3'd7 : ib_count_w[2:0];
    assign debug_o = {
        trace_pc_w[31:0], 2'b0, fetch_stop_w,
        dcache_debug_miss_w, icache_debug_miss_w,
        commit_device_wait_w, commit_div_wait_w, issue_hpm_w[4],
        issue_pair_cause_w, retire_count_w, trap_valid_w,
        f2_redirect_valid_w, branch_redirect_valid_w, icache_debug_miss_w,
        commit_mem_wait_w, issue_wait_w, trace_valid_w[1], trace_valid_w[0],
        alu_debug_mem_valid_w[1] || branch_debug_mem_valid_w[1],
        alu_debug_mem_valid_w[0] || branch_debug_mem_valid_w[0],
        execute1_valid_w, execute0_valid_w, ib_head1_valid_w, ib_head0_valid_w,
        debug_ib_count_w, frontend_active_w[1:0]};
    // The sole class dispatch point uses the issue registered instruction (I06 decision).
    assign execute0_branch_w = execute0_instr_w[6:0] == 7'h63 ||
        execute0_instr_w[6:0] == 7'h67 || execute0_instr_w[6:0] == 7'h6f;
    assign alu_execute0_valid_w = execute0_valid_w && !execute0_branch_w;
    assign branch_execute0_valid_w = execute0_valid_w && execute0_branch_w;
    assign execute0_ready_w = execute0_branch_w ?
        branch_execute0_ready_w : alu_execute0_ready_w;
    // The sole class dispatch point uses the issue registered instruction (I06 decision).
    assign execute1_branch_w = execute1_instr_w[6:0] == 7'h63 ||
        execute1_instr_w[6:0] == 7'h67 || execute1_instr_w[6:0] == 7'h6f;
    assign alu_execute1_valid_w = execute1_valid_w && !execute1_branch_w;
    assign branch_execute1_valid_w = execute1_valid_w && execute1_branch_w;
    assign execute1_ready_w = execute1_branch_w ?
        branch_execute1_ready_w : alu_execute1_ready_w;

    // frontend: frozen per-signal interfaces.
    edrv32_cpu2_frontend #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_frontend (
        .ib_count_o(ib_count_w),
        .frontend_active_o(frontend_active_w),
        .clk_i(clk_i),
        .rst_n_i(rst_frontend_n_w),
        .frontend_flush_i(frontend_flush_w),
        .redirect_valid_i(redirect_valid_w),
        .redirect_pc_i(redirect_pc_w),
        .branch_redirect_valid_i(branch_redirect_valid_w),
        .branch_redirect_tag_i(branch_redirect_tag_w),
        .branch_redirect_pc_i(branch_redirect_pc_w),
        .commit_redirect_valid_i(commit_redirect_valid_w),
        .commit_redirect_pc_i(commit_redirect_pc_w),
        .fetch_stop_i(fetch_stop_w),
        .branch_redirect_ras_data_i(branch_redirect_ras_data_w),
        .branch_redirect_ras_ptr_i(branch_redirect_ras_ptr_w),
        .branch_redirect_ras_count_i(branch_redirect_ras_count_w),
        .branch_redirect_ras_pop_i(branch_redirect_ras_pop_w),
        .branch_redirect_ras_push_i(branch_redirect_ras_push_w),
        .branch_redirect_link_i(branch_redirect_link_w),
        .ib_remove_count_i(ib_remove_count_w),
        .ib_credit_o(ib_credit_w),
        .lvt_i(lvt_w),
        .wb0_valid_i(wb0_valid_w),
        .wb0_rd_i(wb0_rd_w),
        .wb1_valid_i(wb1_valid_w),
        .wb1_rd_i(wb1_rd_w),
        .wb0_valid_copy_i(wb0_valid_copy_w),
        .wb0_rd_copy_i(wb0_rd_copy_w),
        .wb1_valid_copy_i(wb1_valid_copy_w),
        .wb1_rd_copy_i(wb1_rd_copy_w),
        .ib_head0_valid_o(ib_head0_valid_w),
        .ib_head1_valid_o(ib_head1_valid_w),
        .ib_head0_pc_o(ib_head0_pc_w),
        .ib_head0_instr_o(ib_head0_instr_w),
        .ib_head0_error_o(ib_head0_error_w),
        .ib_head0_candidates_o(ib_head0_candidates_w),
        .ib_head0_predict_taken_o(ib_head0_predict_taken_w),
        .ib_head0_predict_target_o(ib_head0_predict_target_w),
        .ib_head0_predict_token_o(ib_head0_predict_token_w),
        .ib_head0_predict_provider_o(ib_head0_predict_provider_w),
        .ib_head0_predict_alternate_o(ib_head0_predict_alternate_w),
        .ib_head0_predict_index0_o(ib_head0_predict_index0_w),
        .ib_head0_predict_index1_o(ib_head0_predict_index1_w),
        .ib_head0_predict_index2_o(ib_head0_predict_index2_w),
        .ib_head0_predict_index3_o(ib_head0_predict_index3_w),
        .ib_head0_predict_tag0_o(ib_head0_predict_tag0_w),
        .ib_head0_predict_tag1_o(ib_head0_predict_tag1_w),
        .ib_head0_predict_tag2_o(ib_head0_predict_tag2_w),
        .ib_head0_predict_tag3_o(ib_head0_predict_tag3_w),
        .ib_head0_predict_base_index_o(ib_head0_predict_base_index_w),
        .ib_head0_predict_fast_index_o(ib_head0_predict_fast_index_w),
        .ib_head0_ras_data_o(ib_head0_ras_data_w),
        .ib_head0_ras_ptr_o(ib_head0_ras_ptr_w),
        .ib_head0_ras_count_o(ib_head0_ras_count_w),
        .ib_head1_pc_o(ib_head1_pc_w),
        .ib_head1_instr_o(ib_head1_instr_w),
        .ib_head1_error_o(ib_head1_error_w),
        .ib_head1_candidates_o(ib_head1_candidates_w),
        .ib_head1_predict_taken_o(ib_head1_predict_taken_w),
        .ib_head1_predict_target_o(ib_head1_predict_target_w),
        .ib_head1_predict_token_o(ib_head1_predict_token_w),
        .ib_head1_predict_provider_o(ib_head1_predict_provider_w),
        .ib_head1_predict_alternate_o(ib_head1_predict_alternate_w),
        .ib_head1_predict_index0_o(ib_head1_predict_index0_w),
        .ib_head1_predict_index1_o(ib_head1_predict_index1_w),
        .ib_head1_predict_index2_o(ib_head1_predict_index2_w),
        .ib_head1_predict_index3_o(ib_head1_predict_index3_w),
        .ib_head1_predict_tag0_o(ib_head1_predict_tag0_w),
        .ib_head1_predict_tag1_o(ib_head1_predict_tag1_w),
        .ib_head1_predict_tag2_o(ib_head1_predict_tag2_w),
        .ib_head1_predict_tag3_o(ib_head1_predict_tag3_w),
        .ib_head1_predict_base_index_o(ib_head1_predict_base_index_w),
        .ib_head1_predict_fast_index_o(ib_head1_predict_fast_index_w),
        .ib_head1_ras_data_o(ib_head1_ras_data_w),
        .ib_head1_ras_ptr_o(ib_head1_ras_ptr_w),
        .ib_head1_ras_count_o(ib_head1_ras_count_w),
        .ic_req_valid_o(ic_req_valid_w),
        .ic_req_ready_i(ic_req_ready_w),
        .ic_req_addr_o(ic_req_addr_w),
        .ic_resp_valid_i(ic_resp_valid_w),
        .ic_resp_ready_o(ic_resp_ready_w),
        .ic_cancel_o(ic_cancel_w),
        .f2_redirect_valid_o(f2_redirect_valid_w),
        .f2_redirect_pc_o(f2_redirect_pc_w),
        .f2_redirect_target_o(f2_redirect_target_w),
        .f2_redirect_cause_o(f2_redirect_cause_w),
        .ic_resp_bank0_way0_instr_i(ic_resp_bank0_way0_instr_w),
        .ic_resp_bank0_way1_instr_i(ic_resp_bank0_way1_instr_w),
        .ic_resp_bank1_way0_instr_i(ic_resp_bank1_way0_instr_w),
        .ic_resp_bank1_way1_instr_i(ic_resp_bank1_way1_instr_w),
        .ic_resp_bank0_way_hit_i(ic_resp_bank0_way_hit_w),
        .ic_resp_bank0_error_i(ic_resp_bank0_error_w),
        .ic_resp_bank1_way_hit_i(ic_resp_bank1_way_hit_w),
        .ic_resp_bank1_error_i(ic_resp_bank1_error_w),
        .predict_read0_valid_i(predict_read0_valid_w),
        .predict_read0_tag_i(predict_read0_tag_w),
        .predict_read0_index0_i(predict_read0_index0_w),
        .predict_read0_index1_i(predict_read0_index1_w),
        .predict_read0_index2_i(predict_read0_index2_w),
        .predict_read0_index3_i(predict_read0_index3_w),
        .predict_read0_tag0_i(predict_read0_tag0_w),
        .predict_read0_tag1_i(predict_read0_tag1_w),
        .predict_read0_tag2_i(predict_read0_tag2_w),
        .predict_read0_tag3_i(predict_read0_tag3_w),
        .predict_read0_base_index_i(predict_read0_base_index_w),
        .predict_read1_valid_i(predict_read1_valid_w),
        .predict_read1_tag_i(predict_read1_tag_w),
        .predict_read1_index0_i(predict_read1_index0_w),
        .predict_read1_index1_i(predict_read1_index1_w),
        .predict_read1_index2_i(predict_read1_index2_w),
        .predict_read1_index3_i(predict_read1_index3_w),
        .predict_read1_tag0_i(predict_read1_tag0_w),
        .predict_read1_tag1_i(predict_read1_tag1_w),
        .predict_read1_tag2_i(predict_read1_tag2_w),
        .predict_read1_tag3_i(predict_read1_tag3_w),
        .predict_read1_base_index_i(predict_read1_base_index_w),
        .ex_predict_train_valid_i(ex_predict_train_valid_w),
        .ex_predict_train_tag_i(ex_predict_train_tag_w),
        .ex_predict_train_pc_i(ex_predict_train_pc_w),
        .ex_predict_train_taken_i(ex_predict_train_taken_w),
        .ex_predict_train_target_i(ex_predict_train_target_w),
        .ex_predict_train_type_i(ex_predict_train_type_w),
        .ex_predict_train_fast_index_i(ex_predict_train_fast_index_w),
        .ex_predict_train_token_i(ex_predict_train_token_w),
        .ex_predict_train_provider_i(ex_predict_train_provider_w),
        .ex_predict_train_prediction_i(ex_predict_train_prediction_w),
        .ex_predict_train_alternate_i(ex_predict_train_alternate_w),
        .ex_predict_train_index0_i(ex_predict_train_index0_w),
        .ex_predict_train_index1_i(ex_predict_train_index1_w),
        .ex_predict_train_index2_i(ex_predict_train_index2_w),
        .ex_predict_train_index3_i(ex_predict_train_index3_w),
        .ex_predict_train_tag0_i(ex_predict_train_tag0_w),
        .ex_predict_train_tag1_i(ex_predict_train_tag1_w),
        .ex_predict_train_tag2_i(ex_predict_train_tag2_w),
        .ex_predict_train_tag3_i(ex_predict_train_tag3_w),
        .ex_predict_train_base_index_i(ex_predict_train_base_index_w),
        .mem_predict_train_valid_i(mem_predict_train_valid_w),
        .mem_predict_train_tag_i(mem_predict_train_tag_w),
        .mem_predict_train_pc_i(mem_predict_train_pc_w),
        .mem_predict_train_taken_i(mem_predict_train_taken_w),
        .mem_predict_train_target_i(mem_predict_train_target_w),
        .mem_predict_train_type_i(mem_predict_train_type_w),
        .mem_predict_train_fast_index_i(mem_predict_train_fast_index_w),
        .mem_predict_train_token_i(mem_predict_train_token_w),
        .mem_predict_train_provider_i(mem_predict_train_provider_w),
        .mem_predict_train_prediction_i(mem_predict_train_prediction_w),
        .mem_predict_train_alternate_i(mem_predict_train_alternate_w),
        .mem_predict_train_index0_i(mem_predict_train_index0_w),
        .mem_predict_train_index1_i(mem_predict_train_index1_w),
        .mem_predict_train_index2_i(mem_predict_train_index2_w),
        .mem_predict_train_index3_i(mem_predict_train_index3_w),
        .mem_predict_train_tag0_i(mem_predict_train_tag0_w),
        .mem_predict_train_tag1_i(mem_predict_train_tag1_w),
        .mem_predict_train_tag2_i(mem_predict_train_tag2_w),
        .mem_predict_train_tag3_i(mem_predict_train_tag3_w),
        .mem_predict_train_base_index_i(mem_predict_train_base_index_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w)
    );

    // Recovery is registered: suppress old IB heads throughout its flush cycle.
    // The IB clears on this edge; issue must not allocate its pre-edge old head.
    wire issue_ib_head0_valid_w;
    wire issue_ib_head1_valid_w;
    assign issue_ib_head0_valid_w = ib_head0_valid_w &&
        !(commit_redirect_valid_w || branch_redirect_valid_w);
    assign issue_ib_head1_valid_w = ib_head1_valid_w &&
        !(commit_redirect_valid_w || branch_redirect_valid_w);
    // issue: frozen per-signal interfaces.
    edrv32_cpu2_issue #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_issue (
        .alu0_complete_valid_i(alu0_complete_valid_w),
        .alu0_complete_ready_i(alu0_complete_ready_w),
        .alu0_complete_tag_i(alu0_complete_tag_w),
        .alu0_complete_data_i(alu0_complete_data_w),
        .alu1_complete_valid_i(alu1_complete_valid_w),
        .alu1_complete_ready_i(alu1_complete_ready_w),
        .alu1_complete_tag_i(alu1_complete_tag_w),
        .alu1_complete_data_i(alu1_complete_data_w),
        .branch_complete_valid_i(branch_complete_valid_w),
        .branch_complete_ready_i(branch_complete_ready_w),
        .branch_complete_tag_i(branch_complete_tag_w),
        .branch_complete_data_i(branch_complete_data_w),
        .mul_complete_valid_i(mul_complete_valid_w),
        .mul_complete_ready_i(mul_complete_ready_w),
        .mul_complete_tag_i(mul_complete_tag_w),
        .mul_complete_data_i(mul_complete_data_w),
        .div_complete_valid_i(div_complete_valid_w),
        .div_complete_ready_i(div_complete_ready_w),
        .div_complete_tag_i(div_complete_tag_w),
        .div_complete_data_i(div_complete_data_w),
        .lsu_complete_valid_i(lsu_complete_valid_w),
        .lsu_complete_ready_i(lsu_complete_ready_w),
        .lsu_complete_tag_i(lsu_complete_tag_w),
        .lsu_complete_data_i(lsu_complete_data_w),
        .csr_complete_valid_i(csr_complete_valid_w),
        .csr_complete_ready_i(csr_complete_ready_w),
        .csr_complete_tag_i(csr_complete_tag_w),
        .csr_complete_data_i(csr_complete_data_w),
        .fp_resp_valid_i(fp_resp_valid_w),
        .fp_resp_ready_i(fp_resp_ready_w),
        .fp_resp_tag_i(fp_resp_tag_w),
        .fp_resp_data_i(fp_resp_data_w),
        .lsu_complete_device_i(lsu_complete_device_w),
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w),
        .csr_fs_i(csr_fs_w),
        .csr_frm_i(csr_frm_w),
        .ib_head0_valid_i(issue_ib_head0_valid_w),
        .ib_head0_pc_i(ib_head0_pc_w),
        .ib_head0_instr_i(ib_head0_instr_w),
        .ib_head0_error_i(ib_head0_error_w),
        .ib_head0_candidates_i(ib_head0_candidates_w),
        .ib_head0_predict_taken_i(ib_head0_predict_taken_w),
        .ib_head0_predict_target_i(ib_head0_predict_target_w),
        .ib_head0_predict_token_i(ib_head0_predict_token_w),
        .ib_head0_predict_provider_i(ib_head0_predict_provider_w),
        .ib_head0_predict_alternate_i(ib_head0_predict_alternate_w),
        .ib_head0_predict_index0_i(ib_head0_predict_index0_w),
        .ib_head0_predict_index1_i(ib_head0_predict_index1_w),
        .ib_head0_predict_index2_i(ib_head0_predict_index2_w),
        .ib_head0_predict_index3_i(ib_head0_predict_index3_w),
        .ib_head0_predict_tag0_i(ib_head0_predict_tag0_w),
        .ib_head0_predict_tag1_i(ib_head0_predict_tag1_w),
        .ib_head0_predict_tag2_i(ib_head0_predict_tag2_w),
        .ib_head0_predict_tag3_i(ib_head0_predict_tag3_w),
        .ib_head0_predict_base_index_i(ib_head0_predict_base_index_w),
        .ib_head0_predict_fast_index_i(ib_head0_predict_fast_index_w),
        .ib_head0_ras_data_i(ib_head0_ras_data_w),
        .ib_head0_ras_ptr_i(ib_head0_ras_ptr_w),
        .ib_head0_ras_count_i(ib_head0_ras_count_w),
        .ib_head1_valid_i(issue_ib_head1_valid_w),
        .ib_head1_pc_i(ib_head1_pc_w),
        .ib_head1_instr_i(ib_head1_instr_w),
        .ib_head1_error_i(ib_head1_error_w),
        .ib_head1_candidates_i(ib_head1_candidates_w),
        .ib_head1_predict_taken_i(ib_head1_predict_taken_w),
        .ib_head1_predict_target_i(ib_head1_predict_target_w),
        .ib_head1_predict_token_i(ib_head1_predict_token_w),
        .ib_head1_predict_provider_i(ib_head1_predict_provider_w),
        .ib_head1_predict_alternate_i(ib_head1_predict_alternate_w),
        .ib_head1_predict_index0_i(ib_head1_predict_index0_w),
        .ib_head1_predict_index1_i(ib_head1_predict_index1_w),
        .ib_head1_predict_index2_i(ib_head1_predict_index2_w),
        .ib_head1_predict_index3_i(ib_head1_predict_index3_w),
        .ib_head1_predict_tag0_i(ib_head1_predict_tag0_w),
        .ib_head1_predict_tag1_i(ib_head1_predict_tag1_w),
        .ib_head1_predict_tag2_i(ib_head1_predict_tag2_w),
        .ib_head1_predict_tag3_i(ib_head1_predict_tag3_w),
        .ib_head1_predict_base_index_i(ib_head1_predict_base_index_w),
        .ib_head1_predict_fast_index_i(ib_head1_predict_fast_index_w),
        .ib_head1_ras_data_i(ib_head1_ras_data_w),
        .ib_head1_ras_ptr_i(ib_head1_ras_ptr_w),
        .ib_head1_ras_count_i(ib_head1_ras_count_w),
        .ib_remove_count_o(ib_remove_count_w),
        .id_rs0_o(id_rs0_w),
        .id_owner0_o(id_owner0_w),
        .id_data0_i(id_data0_w),
        .id_rs1_o(id_rs1_w),
        .id_owner1_o(id_owner1_w),
        .id_data1_i(id_data1_w),
        .id_rs2_o(id_rs2_w),
        .id_owner2_o(id_owner2_w),
        .id_data2_i(id_data2_w),
        .id_rs3_o(id_rs3_w),
        .id_owner3_o(id_owner3_w),
        .id_data3_i(id_data3_w),
        .wb0_valid_i(wb0_valid_w),
        .wb0_rd_i(wb0_rd_w),
        .wb0_data_i(wb0_data_w),
        .wb0_tag_i(wb0_tag_w),
        .wb1_valid_i(wb1_valid_w),
        .wb1_rd_i(wb1_rd_w),
        .wb1_data_i(wb1_data_w),
        .wb1_tag_i(wb1_tag_w),
        .fp_read0_addr_o(fp_read0_addr_w),
        .fp_read0_data_i(fp_read0_data_w),
        .fp_read1_addr_o(fp_read1_addr_w),
        .fp_read1_data_i(fp_read1_data_w),
        .fp_read2_addr_o(fp_read2_addr_w),
        .fp_read2_data_i(fp_read2_data_w),
        .fp_wb_valid_i(fp_wb_valid_w),
        .fp_wb_rd_i(fp_wb_rd_w),
        .fp_wb_data_i(fp_wb_data_w),
        .fp_wb_tag_i(fp_wb_tag_w),
        .allocate_credit_i(allocate_credit_w),
        .allocate_ready_i(allocate_ready_w),
        .allocate_valid_o(allocate_valid_w),
        .allocate_count_o(allocate_count_w),
        .allocate0_tag_o(allocate0_tag_w),
        .allocate0_pc_o(allocate0_pc_w),
        .allocate0_instr_o(allocate0_instr_w),
        .allocate0_rd_o(allocate0_rd_w),
        .allocate0_dest_o(allocate0_dest_w),
        .allocate0_csr_src_o(allocate0_csr_src_w),
        .allocate0_store_o(allocate0_store_w),
        .allocate0_divide_o(allocate0_divide_w),
        .allocate0_double_beat_o(allocate0_double_beat_w),
        .allocate1_tag_o(allocate1_tag_w),
        .allocate1_pc_o(allocate1_pc_w),
        .allocate1_instr_o(allocate1_instr_w),
        .allocate1_rd_o(allocate1_rd_w),
        .allocate1_dest_o(allocate1_dest_w),
        .allocate1_csr_src_o(allocate1_csr_src_w),
        .allocate1_store_o(allocate1_store_w),
        .allocate1_divide_o(allocate1_divide_w),
        .allocate1_double_beat_o(allocate1_double_beat_w),
        .source0_valid_o(source0_valid_w),
        .source0_tag_o(source0_tag_w),
        .source0_domain_o(source0_domain_w),
        .source0_ready_i(source0_ready_w),
        .source0_data_i(source0_data_w),
        .source1_valid_o(source1_valid_w),
        .source1_tag_o(source1_tag_w),
        .source1_domain_o(source1_domain_w),
        .source1_ready_i(source1_ready_w),
        .source1_data_i(source1_data_w),
        .source2_valid_o(source2_valid_w),
        .source2_tag_o(source2_tag_w),
        .source2_domain_o(source2_domain_w),
        .source2_ready_i(source2_ready_w),
        .source2_data_i(source2_data_w),
        .source3_valid_o(source3_valid_w),
        .source3_tag_o(source3_tag_w),
        .source3_domain_o(source3_domain_w),
        .source3_ready_i(source3_ready_w),
        .source3_data_i(source3_data_w),
        .source4_valid_o(source4_valid_w),
        .source4_tag_o(source4_tag_w),
        .source4_domain_o(source4_domain_w),
        .source4_ready_i(source4_ready_w),
        .source4_data_i(source4_data_w),
        .execute0_ready_i(execute0_ready_w),
        .execute0_valid_o(execute0_valid_w),
        .execute0_tag_o(execute0_tag_w),
        .execute0_pc_o(execute0_pc_w),
        .execute0_instr_o(execute0_instr_w),
        .execute0_src1_o(execute0_src1_w),
        .execute0_src2_o(execute0_src2_w),
        .execute0_imm_o(execute0_imm_w),
        .execute0_late_o(execute0_late_w),
        .execute0_source1_tag_o(execute0_source1_tag_w),
        .execute0_source2_tag_o(execute0_source2_tag_w),
        .execute0_source1_wait_o(execute0_source1_wait_w),
        .execute0_source2_wait_o(execute0_source2_wait_w),
        .execute0_predict_taken_o(execute0_predict_taken_w),
        .execute0_predict_target_o(execute0_predict_target_w),
        .execute0_predict_token_o(execute0_predict_token_w),
        .execute0_predict_provider_o(execute0_predict_provider_w),
        .execute0_predict_alternate_o(execute0_predict_alternate_w),
        .execute0_predict_index0_o(execute0_predict_index0_w),
        .execute0_predict_index1_o(execute0_predict_index1_w),
        .execute0_predict_index2_o(execute0_predict_index2_w),
        .execute0_predict_index3_o(execute0_predict_index3_w),
        .execute0_predict_tag0_o(execute0_predict_tag0_w),
        .execute0_predict_tag1_o(execute0_predict_tag1_w),
        .execute0_predict_tag2_o(execute0_predict_tag2_w),
        .execute0_predict_tag3_o(execute0_predict_tag3_w),
        .execute0_predict_base_index_o(execute0_predict_base_index_w),
        .execute0_predict_fast_index_o(execute0_predict_fast_index_w),
        .execute0_ras_data_o(execute0_ras_data_w),
        .execute0_ras_ptr_o(execute0_ras_ptr_w),
        .execute0_ras_count_o(execute0_ras_count_w),
        .execute1_ready_i(execute1_ready_w),
        .execute1_valid_o(execute1_valid_w),
        .execute1_tag_o(execute1_tag_w),
        .execute1_pc_o(execute1_pc_w),
        .execute1_instr_o(execute1_instr_w),
        .execute1_src1_o(execute1_src1_w),
        .execute1_src2_o(execute1_src2_w),
        .execute1_imm_o(execute1_imm_w),
        .execute1_late_o(execute1_late_w),
        .execute1_source1_tag_o(execute1_source1_tag_w),
        .execute1_source2_tag_o(execute1_source2_tag_w),
        .execute1_source1_wait_o(execute1_source1_wait_w),
        .execute1_source2_wait_o(execute1_source2_wait_w),
        .execute1_predict_taken_o(execute1_predict_taken_w),
        .execute1_predict_target_o(execute1_predict_target_w),
        .execute1_predict_token_o(execute1_predict_token_w),
        .execute1_predict_provider_o(execute1_predict_provider_w),
        .execute1_predict_alternate_o(execute1_predict_alternate_w),
        .execute1_predict_index0_o(execute1_predict_index0_w),
        .execute1_predict_index1_o(execute1_predict_index1_w),
        .execute1_predict_index2_o(execute1_predict_index2_w),
        .execute1_predict_index3_o(execute1_predict_index3_w),
        .execute1_predict_tag0_o(execute1_predict_tag0_w),
        .execute1_predict_tag1_o(execute1_predict_tag1_w),
        .execute1_predict_tag2_o(execute1_predict_tag2_w),
        .execute1_predict_tag3_o(execute1_predict_tag3_w),
        .execute1_predict_base_index_o(execute1_predict_base_index_w),
        .execute1_predict_fast_index_o(execute1_predict_fast_index_w),
        .execute1_ras_data_o(execute1_ras_data_w),
        .execute1_ras_ptr_o(execute1_ras_ptr_w),
        .execute1_ras_count_o(execute1_ras_count_w),
        .mul_req_ready_i(mul_req_ready_w),
        .mul_req_valid_o(mul_req_valid_w),
        .mul_req_tag_o(mul_req_tag_w),
        .mul_req_instr_o(mul_req_instr_w),
        .mul_req_src1_o(mul_req_src1_w),
        .mul_req_src2_o(mul_req_src2_w),
        .div_req_ready_i(div_req_ready_w),
        .div_req_valid_o(div_req_valid_w),
        .div_req_tag_o(div_req_tag_w),
        .div_req_instr_o(div_req_instr_w),
        .div_req_src1_o(div_req_src1_w),
        .div_req_src2_o(div_req_src2_w),
        .lsu_req_ready_i(lsu_req_ready_w),
        .lsu_req_valid_o(lsu_req_valid_w),
        .lsu_req_tag_o(lsu_req_tag_w),
        .lsu_req_instr_o(lsu_req_instr_w),
        .lsu_req_addr_o(lsu_req_addr_w),
        .lsu_req_store_data_o(lsu_req_store_data_w),
        .lsu_req_early_o(lsu_req_early_w),
        .csr_req_ready_i(csr_req_ready_w),
        .csr_req_valid_o(csr_req_valid_w),
        .csr_req_tag_o(csr_req_tag_w),
        .csr_req_instr_o(csr_req_instr_w),
        .csr_req_src_o(csr_req_src_w),
        .fp_req_ready_i(fp_req_ready_w),
        .fp_req_valid_o(fp_req_valid_w),
        .fp_req_tag_o(fp_req_tag_w),
        .fp_req_instr_o(fp_req_instr_w),
        .fp_req_src1_o(fp_req_src1_w),
        .fp_req_src2_o(fp_req_src2_w),
        .fp_req_src3_o(fp_req_src3_w),
        .fp_req_int_src_o(fp_req_int_src_w),
        .fp_req_rm_o(fp_req_rm_w),
        .early_req_valid_o(early_req_valid_w),
        .early_req_addr_o(early_req_addr_w),
        .early_req_tag_o(early_req_tag_w),
        .decode_complete_ready_i(decode_complete_ready_w),
        .decode_complete_valid_o(decode_complete_valid_w),
        .decode_complete_tag_o(decode_complete_tag_w),
        .decode_complete_exception_o(decode_complete_exception_w),
        .decode_complete_cause_o(decode_complete_cause_w),
        .decode_complete_tval_o(decode_complete_tval_w),
        .predict_read0_valid_o(predict_read0_valid_w),
        .predict_read0_tag_o(predict_read0_tag_w),
        .predict_read0_index0_o(predict_read0_index0_w),
        .predict_read0_index1_o(predict_read0_index1_w),
        .predict_read0_index2_o(predict_read0_index2_w),
        .predict_read0_index3_o(predict_read0_index3_w),
        .predict_read0_tag0_o(predict_read0_tag0_w),
        .predict_read0_tag1_o(predict_read0_tag1_w),
        .predict_read0_tag2_o(predict_read0_tag2_w),
        .predict_read0_tag3_o(predict_read0_tag3_w),
        .predict_read0_base_index_o(predict_read0_base_index_w),
        .predict_read1_valid_o(predict_read1_valid_w),
        .predict_read1_tag_o(predict_read1_tag_w),
        .predict_read1_index0_o(predict_read1_index0_w),
        .predict_read1_index1_o(predict_read1_index1_w),
        .predict_read1_index2_o(predict_read1_index2_w),
        .predict_read1_index3_o(predict_read1_index3_w),
        .predict_read1_tag0_o(predict_read1_tag0_w),
        .predict_read1_tag1_o(predict_read1_tag1_w),
        .predict_read1_tag2_o(predict_read1_tag2_w),
        .predict_read1_tag3_o(predict_read1_tag3_w),
        .predict_read1_base_index_o(predict_read1_base_index_w),
        .issue_hpm_o(issue_hpm_w),
        .issue_pair_cause_o(issue_pair_cause_w),
        .issue_wait_o(issue_wait_w)
    );

    // rf: frozen per-signal interfaces.
    edrv32_cpu2_rf #(
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_rf (
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .id_rs0_i(id_rs0_w),
        .id_owner0_i(id_owner0_w),
        .id_data0_o(id_data0_w),
        .id_rs1_i(id_rs1_w),
        .id_owner1_i(id_owner1_w),
        .id_data1_o(id_data1_w),
        .id_rs2_i(id_rs2_w),
        .id_owner2_i(id_owner2_w),
        .id_data2_o(id_data2_w),
        .id_rs3_i(id_rs3_w),
        .id_owner3_i(id_owner3_w),
        .id_data3_o(id_data3_w),
        .wb0_valid_i(wb0_valid_w),
        .wb0_rd_i(wb0_rd_w),
        .wb0_data_i(wb0_data_w),
        .wb1_valid_i(wb1_valid_w),
        .wb1_rd_i(wb1_rd_w),
        .wb1_data_i(wb1_data_w),
        .lvt_o(lvt_w)
    );

    // alu: frozen per-signal interfaces.
    edrv32_cpu2_alu #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_alu (
        .lsu_complete_device_i(lsu_complete_device_w),
        .wb0_valid_i(wb0_valid_w),
        .wb0_tag_i(wb0_tag_w),
        .wb0_data_i(wb0_data_w),
        .wb1_valid_i(wb1_valid_w),
        .wb1_tag_i(wb1_tag_w),
        .wb1_data_i(wb1_data_w),
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w),
        .execute0_valid_i(alu_execute0_valid_w),
        .execute0_ready_o(alu_execute0_ready_w),
        .execute0_tag_i(execute0_tag_w),
        .execute0_pc_i(execute0_pc_w),
        .execute0_instr_i(execute0_instr_w),
        .execute0_src1_i(execute0_src1_w),
        .execute0_src2_i(execute0_src2_w),
        .execute0_imm_i(execute0_imm_w),
        .execute0_late_i(execute0_late_w),
        .execute0_source1_tag_i(execute0_source1_tag_w),
        .execute0_source2_tag_i(execute0_source2_tag_w),
        .execute0_source1_wait_i(execute0_source1_wait_w),
        .execute0_source2_wait_i(execute0_source2_wait_w),
        .execute1_valid_i(alu_execute1_valid_w),
        .execute1_ready_o(alu_execute1_ready_w),
        .execute1_tag_i(execute1_tag_w),
        .execute1_pc_i(execute1_pc_w),
        .execute1_instr_i(execute1_instr_w),
        .execute1_src1_i(execute1_src1_w),
        .execute1_src2_i(execute1_src2_w),
        .execute1_imm_i(execute1_imm_w),
        .execute1_late_i(execute1_late_w),
        .execute1_source1_tag_i(execute1_source1_tag_w),
        .execute1_source2_tag_i(execute1_source2_tag_w),
        .execute1_source1_wait_i(execute1_source1_wait_w),
        .execute1_source2_wait_i(execute1_source2_wait_w),
        .alu0_complete_valid_i(alu0_complete_valid_w),
        .alu0_complete_ready_i(alu0_complete_ready_w),
        .alu0_complete_tag_i(alu0_complete_tag_w),
        .alu0_complete_data_i(alu0_complete_data_w),
        .alu1_complete_valid_i(alu1_complete_valid_w),
        .alu1_complete_ready_i(alu1_complete_ready_w),
        .alu1_complete_tag_i(alu1_complete_tag_w),
        .alu1_complete_data_i(alu1_complete_data_w),
        .branch_complete_valid_i(branch_complete_valid_w),
        .branch_complete_ready_i(branch_complete_ready_w),
        .branch_complete_tag_i(branch_complete_tag_w),
        .branch_complete_data_i(branch_complete_data_w),
        .mul_complete_valid_i(mul_complete_valid_w),
        .mul_complete_ready_i(mul_complete_ready_w),
        .mul_complete_tag_i(mul_complete_tag_w),
        .mul_complete_data_i(mul_complete_data_w),
        .div_complete_valid_i(div_complete_valid_w),
        .div_complete_ready_i(div_complete_ready_w),
        .div_complete_tag_i(div_complete_tag_w),
        .div_complete_data_i(div_complete_data_w),
        .lsu_complete_valid_i(lsu_complete_valid_w),
        .lsu_complete_ready_i(lsu_complete_ready_w),
        .lsu_complete_tag_i(lsu_complete_tag_w),
        .lsu_complete_data_i(lsu_complete_data_w),
        .csr_complete_valid_i(csr_complete_valid_w),
        .csr_complete_ready_i(csr_complete_ready_w),
        .csr_complete_tag_i(csr_complete_tag_w),
        .csr_complete_data_i(csr_complete_data_w),
        .fp_resp_valid_i(fp_resp_valid_w),
        .fp_resp_ready_i(fp_resp_ready_w),
        .fp_resp_tag_i(fp_resp_tag_w),
        .fp_resp_data_i(fp_resp_data_w),
        .alu0_complete_valid_o(alu0_complete_valid_w),
        .alu0_complete_tag_o(alu0_complete_tag_w),
        .alu0_complete_data_o(alu0_complete_data_w),
        .alu0_complete_flags_o(alu0_complete_flags_w),
        .alu0_complete_exception_o(alu0_complete_exception_w),
        .alu0_complete_cause_o(alu0_complete_cause_w),
        .alu0_complete_tval_o(alu0_complete_tval_w),
        .alu1_complete_valid_o(alu1_complete_valid_w),
        .alu1_complete_tag_o(alu1_complete_tag_w),
        .alu1_complete_data_o(alu1_complete_data_w),
        .alu1_complete_flags_o(alu1_complete_flags_w),
        .alu1_complete_exception_o(alu1_complete_exception_w),
        .alu1_complete_cause_o(alu1_complete_cause_w),
        .alu1_complete_tval_o(alu1_complete_tval_w),
        .debug_mem_valid_o(alu_debug_mem_valid_w)
    );

    // branch: frozen per-signal interfaces.
    edrv32_cpu2_branch #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_branch (
        .lsu_complete_device_i(lsu_complete_device_w),
        .wb0_valid_i(wb0_valid_w),
        .wb0_tag_i(wb0_tag_w),
        .wb0_data_i(wb0_data_w),
        .wb1_valid_i(wb1_valid_w),
        .wb1_tag_i(wb1_tag_w),
        .wb1_data_i(wb1_data_w),
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w),
        .execute0_valid_i(branch_execute0_valid_w),
        .execute0_tag_i(execute0_tag_w),
        .execute0_pc_i(execute0_pc_w),
        .execute0_instr_i(execute0_instr_w),
        .execute0_src1_i(execute0_src1_w),
        .execute0_src2_i(execute0_src2_w),
        .execute0_imm_i(execute0_imm_w),
        .execute0_late_i(execute0_late_w),
        .execute0_source1_tag_i(execute0_source1_tag_w),
        .execute0_source2_tag_i(execute0_source2_tag_w),
        .execute0_source1_wait_i(execute0_source1_wait_w),
        .execute0_source2_wait_i(execute0_source2_wait_w),
        .execute0_predict_taken_i(execute0_predict_taken_w),
        .execute0_predict_target_i(execute0_predict_target_w),
        .execute0_predict_token_i(execute0_predict_token_w),
        .execute0_predict_provider_i(execute0_predict_provider_w),
        .execute0_predict_alternate_i(execute0_predict_alternate_w),
        .execute0_predict_index0_i(execute0_predict_index0_w),
        .execute0_predict_index1_i(execute0_predict_index1_w),
        .execute0_predict_index2_i(execute0_predict_index2_w),
        .execute0_predict_index3_i(execute0_predict_index3_w),
        .execute0_predict_tag0_i(execute0_predict_tag0_w),
        .execute0_predict_tag1_i(execute0_predict_tag1_w),
        .execute0_predict_tag2_i(execute0_predict_tag2_w),
        .execute0_predict_tag3_i(execute0_predict_tag3_w),
        .execute0_predict_base_index_i(execute0_predict_base_index_w),
        .execute0_predict_fast_index_i(execute0_predict_fast_index_w),
        .execute0_ras_data_i(execute0_ras_data_w),
        .execute0_ras_ptr_i(execute0_ras_ptr_w),
        .execute0_ras_count_i(execute0_ras_count_w),
        .execute0_ready_o(branch_execute0_ready_w),
        .execute1_valid_i(branch_execute1_valid_w),
        .execute1_tag_i(execute1_tag_w),
        .execute1_pc_i(execute1_pc_w),
        .execute1_instr_i(execute1_instr_w),
        .execute1_src1_i(execute1_src1_w),
        .execute1_src2_i(execute1_src2_w),
        .execute1_imm_i(execute1_imm_w),
        .execute1_late_i(execute1_late_w),
        .execute1_source1_tag_i(execute1_source1_tag_w),
        .execute1_source2_tag_i(execute1_source2_tag_w),
        .execute1_source1_wait_i(execute1_source1_wait_w),
        .execute1_source2_wait_i(execute1_source2_wait_w),
        .execute1_predict_taken_i(execute1_predict_taken_w),
        .execute1_predict_target_i(execute1_predict_target_w),
        .execute1_predict_token_i(execute1_predict_token_w),
        .execute1_predict_provider_i(execute1_predict_provider_w),
        .execute1_predict_alternate_i(execute1_predict_alternate_w),
        .execute1_predict_index0_i(execute1_predict_index0_w),
        .execute1_predict_index1_i(execute1_predict_index1_w),
        .execute1_predict_index2_i(execute1_predict_index2_w),
        .execute1_predict_index3_i(execute1_predict_index3_w),
        .execute1_predict_tag0_i(execute1_predict_tag0_w),
        .execute1_predict_tag1_i(execute1_predict_tag1_w),
        .execute1_predict_tag2_i(execute1_predict_tag2_w),
        .execute1_predict_tag3_i(execute1_predict_tag3_w),
        .execute1_predict_base_index_i(execute1_predict_base_index_w),
        .execute1_predict_fast_index_i(execute1_predict_fast_index_w),
        .execute1_ras_data_i(execute1_ras_data_w),
        .execute1_ras_ptr_i(execute1_ras_ptr_w),
        .execute1_ras_count_i(execute1_ras_count_w),
        .execute1_ready_o(branch_execute1_ready_w),
        .alu0_complete_valid_i(alu0_complete_valid_w),
        .alu0_complete_ready_i(alu0_complete_ready_w),
        .alu0_complete_tag_i(alu0_complete_tag_w),
        .alu0_complete_data_i(alu0_complete_data_w),
        .alu1_complete_valid_i(alu1_complete_valid_w),
        .alu1_complete_ready_i(alu1_complete_ready_w),
        .alu1_complete_tag_i(alu1_complete_tag_w),
        .alu1_complete_data_i(alu1_complete_data_w),
        .branch_complete_valid_i(branch_complete_valid_w),
        .branch_complete_ready_i(branch_complete_ready_w),
        .branch_complete_tag_i(branch_complete_tag_w),
        .branch_complete_data_i(branch_complete_data_w),
        .mul_complete_valid_i(mul_complete_valid_w),
        .mul_complete_ready_i(mul_complete_ready_w),
        .mul_complete_tag_i(mul_complete_tag_w),
        .mul_complete_data_i(mul_complete_data_w),
        .div_complete_valid_i(div_complete_valid_w),
        .div_complete_ready_i(div_complete_ready_w),
        .div_complete_tag_i(div_complete_tag_w),
        .div_complete_data_i(div_complete_data_w),
        .lsu_complete_valid_i(lsu_complete_valid_w),
        .lsu_complete_ready_i(lsu_complete_ready_w),
        .lsu_complete_tag_i(lsu_complete_tag_w),
        .lsu_complete_data_i(lsu_complete_data_w),
        .csr_complete_valid_i(csr_complete_valid_w),
        .csr_complete_ready_i(csr_complete_ready_w),
        .csr_complete_tag_i(csr_complete_tag_w),
        .csr_complete_data_i(csr_complete_data_w),
        .fp_resp_valid_i(fp_resp_valid_w),
        .fp_resp_ready_i(fp_resp_ready_w),
        .fp_resp_tag_i(fp_resp_tag_w),
        .fp_resp_data_i(fp_resp_data_w),
        .branch_complete_valid_o(branch_complete_valid_w),
        .branch_complete_tag_o(branch_complete_tag_w),
        .branch_complete_data_o(branch_complete_data_w),
        .branch_complete_flags_o(branch_complete_flags_w),
        .branch_complete_exception_o(branch_complete_exception_w),
        .branch_complete_cause_o(branch_complete_cause_w),
        .branch_complete_tval_o(branch_complete_tval_w),
        .branch_complete_next_pc_o(branch_complete_next_pc_w),
        .ex_predict_train_valid_o(ex_predict_train_valid_w),
        .ex_predict_train_tag_o(ex_predict_train_tag_w),
        .ex_predict_train_pc_o(ex_predict_train_pc_w),
        .ex_predict_train_taken_o(ex_predict_train_taken_w),
        .ex_predict_train_target_o(ex_predict_train_target_w),
        .ex_predict_train_type_o(ex_predict_train_type_w),
        .ex_predict_train_token_o(ex_predict_train_token_w),
        .ex_predict_train_provider_o(ex_predict_train_provider_w),
        .ex_predict_train_alternate_o(ex_predict_train_alternate_w),
        .ex_predict_train_prediction_o(ex_predict_train_prediction_w),
        .ex_predict_train_index0_o(ex_predict_train_index0_w),
        .ex_predict_train_index1_o(ex_predict_train_index1_w),
        .ex_predict_train_index2_o(ex_predict_train_index2_w),
        .ex_predict_train_index3_o(ex_predict_train_index3_w),
        .ex_predict_train_tag0_o(ex_predict_train_tag0_w),
        .ex_predict_train_tag1_o(ex_predict_train_tag1_w),
        .ex_predict_train_tag2_o(ex_predict_train_tag2_w),
        .ex_predict_train_tag3_o(ex_predict_train_tag3_w),
        .ex_predict_train_base_index_o(ex_predict_train_base_index_w),
        .ex_predict_train_fast_index_o(ex_predict_train_fast_index_w),
        .mem_predict_train_valid_o(mem_predict_train_valid_w),
        .mem_predict_train_tag_o(mem_predict_train_tag_w),
        .mem_predict_train_pc_o(mem_predict_train_pc_w),
        .mem_predict_train_taken_o(mem_predict_train_taken_w),
        .mem_predict_train_target_o(mem_predict_train_target_w),
        .mem_predict_train_type_o(mem_predict_train_type_w),
        .mem_predict_train_token_o(mem_predict_train_token_w),
        .mem_predict_train_provider_o(mem_predict_train_provider_w),
        .mem_predict_train_alternate_o(mem_predict_train_alternate_w),
        .mem_predict_train_prediction_o(mem_predict_train_prediction_w),
        .mem_predict_train_index0_o(mem_predict_train_index0_w),
        .mem_predict_train_index1_o(mem_predict_train_index1_w),
        .mem_predict_train_index2_o(mem_predict_train_index2_w),
        .mem_predict_train_index3_o(mem_predict_train_index3_w),
        .mem_predict_train_tag0_o(mem_predict_train_tag0_w),
        .mem_predict_train_tag1_o(mem_predict_train_tag1_w),
        .mem_predict_train_tag2_o(mem_predict_train_tag2_w),
        .mem_predict_train_tag3_o(mem_predict_train_tag3_w),
        .mem_predict_train_base_index_o(mem_predict_train_base_index_w),
        .mem_predict_train_fast_index_o(mem_predict_train_fast_index_w),
        .branch_redirect_valid_o(branch_redirect_valid_w),
        .branch_redirect_tag_o(branch_redirect_tag_w),
        .branch_redirect_pc_o(branch_redirect_pc_w),
        .branch_redirect_ras_data_o(branch_redirect_ras_data_w),
        .branch_redirect_ras_ptr_o(branch_redirect_ras_ptr_w),
        .branch_redirect_ras_count_o(branch_redirect_ras_count_w),
        .branch_redirect_ras_pop_o(branch_redirect_ras_pop_w),
        .branch_redirect_ras_push_o(branch_redirect_ras_push_w),
        .branch_redirect_link_o(branch_redirect_link_w),
        .trace_branch_pc_o(trace_branch_pc_w),
        .trace_branch_stage_o(trace_branch_stage_w),
        .trace_branch_cause_o(trace_branch_cause_w),
        .debug_mem_valid_o(branch_debug_mem_valid_w)
    );

    // mul: frozen per-signal interfaces.
    edrv32_cpu2_mul #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_mul (
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .mul_req_valid_i(mul_req_valid_w),
        .mul_req_ready_o(mul_req_ready_w),
        .mul_req_tag_i(mul_req_tag_w),
        .mul_req_instr_i(mul_req_instr_w),
        .mul_req_src1_i(mul_req_src1_w),
        .mul_req_src2_i(mul_req_src2_w),
        .mul_complete_valid_o(mul_complete_valid_w),
        .mul_complete_ready_i(mul_complete_ready_w),
        .mul_complete_tag_o(mul_complete_tag_w),
        .mul_complete_data_o(mul_complete_data_w),
        .mul_complete_flags_o(mul_complete_flags_w),
        .mul_complete_exception_o(mul_complete_exception_w),
        .mul_complete_cause_o(mul_complete_cause_w),
        .mul_complete_tval_o(mul_complete_tval_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w)
    );

    // div: frozen per-signal interfaces.
    edrv32_cpu2_div #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_div (
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .div_req_valid_i(div_req_valid_w),
        .div_req_ready_o(div_req_ready_w),
        .div_req_tag_i(div_req_tag_w),
        .div_req_instr_i(div_req_instr_w),
        .div_req_src1_i(div_req_src1_w),
        .div_req_src2_i(div_req_src2_w),
        .div_complete_valid_o(div_complete_valid_w),
        .div_complete_ready_i(div_complete_ready_w),
        .div_complete_tag_o(div_complete_tag_w),
        .div_complete_data_o(div_complete_data_w),
        .div_complete_flags_o(div_complete_flags_w),
        .div_complete_exception_o(div_complete_exception_w),
        .div_complete_cause_o(div_complete_cause_w),
        .div_complete_tval_o(div_complete_tval_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w)
    );

    // completion: frozen per-signal interfaces.
    edrv32_cpu2_completion #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_completion (
        .clk_i(clk_i),
        .rst_n_i(rst_commit_cache_n_w),
        .allocate_valid_i(allocate_valid_w),
        .allocate_count_i(allocate_count_w),
        .allocate_ready_o(allocate_ready_w),
        .allocate_credit_o(allocate_credit_w),
        .retire_count_i(retire_count_w),
        .commit_cancel_valid_i(commit_cancel_valid_w),
        .commit_cancel_tag_i(commit_cancel_tag_w),
        .branch_redirect_valid_i(branch_redirect_valid_w),
        .branch_redirect_tag_i(branch_redirect_tag_w),
        .branch_redirect_pc_i(branch_redirect_pc_w),
        .age_head_o(age_head_w),
        .cancel_valid_o(cancel_valid_w),
        .cancel_tag_o(cancel_tag_w),
        .allocate0_tag_i(allocate0_tag_w),
        .allocate0_pc_i(allocate0_pc_w),
        .allocate0_instr_i(allocate0_instr_w),
        .allocate0_rd_i(allocate0_rd_w),
        .allocate0_dest_i(allocate0_dest_w),
        .allocate0_csr_src_i(allocate0_csr_src_w),
        .allocate0_store_i(allocate0_store_w),
        .allocate0_divide_i(allocate0_divide_w),
        .allocate0_double_beat_i(allocate0_double_beat_w),
        .head0_tag_o(head0_tag_w),
        .head0_pc_o(head0_pc_w),
        .head0_next_pc_o(head0_next_pc_w),
        .head0_kind_o(head0_kind_w),
        .head0_trace_instr_o(head0_trace_instr_w),
        .head0_rd_o(head0_rd_w),
        .head0_dest_o(head0_dest_w),
        .head0_store_o(head0_store_w),
        .head0_divide_o(head0_divide_w),
        .head0_double_beat_o(head0_double_beat_w),
        .head0_valid_o(head0_valid_w),
        .head0_done_o(head0_done_w),
        .head0_data_o(head0_data_w),
        .head0_flags_o(head0_flags_w),
        .head0_exception_o(head0_exception_w),
        .head0_cause_o(head0_cause_w),
        .head0_tval_o(head0_tval_w),
        .head0_device_o(head0_device_w),
        .head0_mem_addr_o(head0_mem_addr_w),
        .head0_mem_data_o(head0_mem_data_w),
        .head0_mem_mask_o(head0_mem_mask_w),
        .allocate1_tag_i(allocate1_tag_w),
        .allocate1_pc_i(allocate1_pc_w),
        .allocate1_instr_i(allocate1_instr_w),
        .allocate1_rd_i(allocate1_rd_w),
        .allocate1_dest_i(allocate1_dest_w),
        .allocate1_csr_src_i(allocate1_csr_src_w),
        .allocate1_store_i(allocate1_store_w),
        .allocate1_divide_i(allocate1_divide_w),
        .allocate1_double_beat_i(allocate1_double_beat_w),
        .head1_tag_o(head1_tag_w),
        .head1_pc_o(head1_pc_w),
        .head1_next_pc_o(head1_next_pc_w),
        .head1_kind_o(head1_kind_w),
        .head1_trace_instr_o(head1_trace_instr_w),
        .head1_rd_o(head1_rd_w),
        .head1_dest_o(head1_dest_w),
        .head1_store_o(head1_store_w),
        .head1_divide_o(head1_divide_w),
        .head1_double_beat_o(head1_double_beat_w),
        .head1_valid_o(head1_valid_w),
        .head1_done_o(head1_done_w),
        .head1_data_o(head1_data_w),
        .head1_flags_o(head1_flags_w),
        .head1_exception_o(head1_exception_w),
        .head1_cause_o(head1_cause_w),
        .head1_tval_o(head1_tval_w),
        .head1_device_o(head1_device_w),
        .head1_mem_addr_o(head1_mem_addr_w),
        .head1_mem_data_o(head1_mem_data_w),
        .head1_mem_mask_o(head1_mem_mask_w),
        .source0_tag_i(source0_tag_w),
        .source0_valid_i(source0_valid_w),
        .source0_domain_i(source0_domain_w),
        .source0_ready_o(source0_ready_w),
        .source0_data_o(source0_data_w),
        .source1_tag_i(source1_tag_w),
        .source1_valid_i(source1_valid_w),
        .source1_domain_i(source1_domain_w),
        .source1_ready_o(source1_ready_w),
        .source1_data_o(source1_data_w),
        .source2_tag_i(source2_tag_w),
        .source2_valid_i(source2_valid_w),
        .source2_domain_i(source2_domain_w),
        .source2_ready_o(source2_ready_w),
        .source2_data_o(source2_data_w),
        .source3_tag_i(source3_tag_w),
        .source3_valid_i(source3_valid_w),
        .source3_domain_i(source3_domain_w),
        .source3_ready_o(source3_ready_w),
        .source3_data_o(source3_data_w),
        .source4_tag_i(source4_tag_w),
        .source4_valid_i(source4_valid_w),
        .source4_domain_i(source4_domain_w),
        .source4_ready_o(source4_ready_w),
        .source4_data_o(source4_data_w),
        .alu0_complete_valid_i(alu0_complete_valid_w),
        .alu0_complete_tag_i(alu0_complete_tag_w),
        .alu0_complete_data_i(alu0_complete_data_w),
        .alu0_complete_flags_i(alu0_complete_flags_w),
        .alu0_complete_exception_i(alu0_complete_exception_w),
        .alu0_complete_cause_i(alu0_complete_cause_w),
        .alu0_complete_tval_i(alu0_complete_tval_w),
        .alu0_complete_ready_o(alu0_complete_ready_w),
        .alu1_complete_valid_i(alu1_complete_valid_w),
        .alu1_complete_tag_i(alu1_complete_tag_w),
        .alu1_complete_data_i(alu1_complete_data_w),
        .alu1_complete_flags_i(alu1_complete_flags_w),
        .alu1_complete_exception_i(alu1_complete_exception_w),
        .alu1_complete_cause_i(alu1_complete_cause_w),
        .alu1_complete_tval_i(alu1_complete_tval_w),
        .alu1_complete_ready_o(alu1_complete_ready_w),
        .branch_complete_next_pc_i(branch_complete_next_pc_w),
        .branch_complete_valid_i(branch_complete_valid_w),
        .branch_complete_tag_i(branch_complete_tag_w),
        .branch_complete_data_i(branch_complete_data_w),
        .branch_complete_flags_i(branch_complete_flags_w),
        .branch_complete_exception_i(branch_complete_exception_w),
        .branch_complete_cause_i(branch_complete_cause_w),
        .branch_complete_tval_i(branch_complete_tval_w),
        .branch_complete_ready_o(branch_complete_ready_w),
        .mul_complete_valid_i(mul_complete_valid_w),
        .mul_complete_tag_i(mul_complete_tag_w),
        .mul_complete_data_i(mul_complete_data_w),
        .mul_complete_flags_i(mul_complete_flags_w),
        .mul_complete_exception_i(mul_complete_exception_w),
        .mul_complete_cause_i(mul_complete_cause_w),
        .mul_complete_tval_i(mul_complete_tval_w),
        .mul_complete_ready_o(mul_complete_ready_w),
        .div_complete_valid_i(div_complete_valid_w),
        .div_complete_tag_i(div_complete_tag_w),
        .div_complete_data_i(div_complete_data_w),
        .div_complete_flags_i(div_complete_flags_w),
        .div_complete_exception_i(div_complete_exception_w),
        .div_complete_cause_i(div_complete_cause_w),
        .div_complete_tval_i(div_complete_tval_w),
        .div_complete_ready_o(div_complete_ready_w),
        .lsu_complete_valid_i(lsu_complete_valid_w),
        .lsu_complete_tag_i(lsu_complete_tag_w),
        .lsu_complete_data_i(lsu_complete_data_w),
        .lsu_complete_flags_i(lsu_complete_flags_w),
        .lsu_complete_exception_i(lsu_complete_exception_w),
        .lsu_complete_cause_i(lsu_complete_cause_w),
        .lsu_complete_tval_i(lsu_complete_tval_w),
        .lsu_complete_ready_o(lsu_complete_ready_w),
        .csr_complete_valid_i(csr_complete_valid_w),
        .csr_complete_tag_i(csr_complete_tag_w),
        .csr_complete_data_i(csr_complete_data_w),
        .csr_complete_flags_i(csr_complete_flags_w),
        .csr_complete_exception_i(csr_complete_exception_w),
        .csr_complete_cause_i(csr_complete_cause_w),
        .csr_complete_tval_i(csr_complete_tval_w),
        .csr_complete_ready_o(csr_complete_ready_w),
        .fp_resp_valid_i(fp_resp_valid_w),
        .fp_resp_tag_i(fp_resp_tag_w),
        .fp_resp_data_i(fp_resp_data_w),
        .fp_resp_flags_i(fp_resp_flags_w),
        .fp_resp_ready_o(fp_resp_ready_w),
        .decode_complete_valid_i(decode_complete_valid_w),
        .decode_complete_tag_i(decode_complete_tag_w),
        .decode_complete_exception_i(decode_complete_exception_w),
        .decode_complete_cause_i(decode_complete_cause_w),
        .decode_complete_tval_i(decode_complete_tval_w),
        .decode_complete_ready_o(decode_complete_ready_w),
        .fp_resp_int_dest_i(fp_resp_int_dest_w),
        .lsu_complete_device_i(lsu_complete_device_w),
        .lsu_complete_mem_addr_i(lsu_complete_mem_addr_w),
        .lsu_complete_mem_data_i(lsu_complete_mem_data_w),
        .lsu_complete_mem_mask_i(lsu_complete_mem_mask_w)
    );

    // commit: frozen per-signal interfaces.
    edrv32_cpu2_commit #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_commit (
        .clk_i(clk_i),
        .rst_n_i(rst_commit_cache_n_w),
        .head0_tag_i(head0_tag_w),
        .head0_pc_i(head0_pc_w),
        .head0_next_pc_i(head0_next_pc_w),
        .head0_kind_i(head0_kind_w),
        .head0_trace_instr_i(head0_trace_instr_w),
        .head0_rd_i(head0_rd_w),
        .head0_dest_i(head0_dest_w),
        .head0_store_i(head0_store_w),
        .head0_divide_i(head0_divide_w),
        .head0_double_beat_i(head0_double_beat_w),
        .head0_valid_i(head0_valid_w),
        .head0_done_i(head0_done_w),
        .head0_data_i(head0_data_w),
        .head0_flags_i(head0_flags_w),
        .head0_exception_i(head0_exception_w),
        .head0_cause_i(head0_cause_w),
        .head0_tval_i(head0_tval_w),
        .head0_device_i(head0_device_w),
        .head0_mem_addr_i(head0_mem_addr_w),
        .head0_mem_data_i(head0_mem_data_w),
        .head0_mem_mask_i(head0_mem_mask_w),
        .wb0_tag_o(wb0_tag_w),
        .wb0_valid_copy_o(wb0_valid_copy_w),
        .wb0_rd_copy_o(wb0_rd_copy_w),
        .wb0_valid_o(wb0_valid_w),
        .wb0_rd_o(wb0_rd_w),
        .wb0_data_o(wb0_data_w),
        .head1_tag_i(head1_tag_w),
        .head1_pc_i(head1_pc_w),
        .head1_next_pc_i(head1_next_pc_w),
        .head1_kind_i(head1_kind_w),
        .head1_trace_instr_i(head1_trace_instr_w),
        .head1_rd_i(head1_rd_w),
        .head1_dest_i(head1_dest_w),
        .head1_store_i(head1_store_w),
        .head1_divide_i(head1_divide_w),
        .head1_double_beat_i(head1_double_beat_w),
        .head1_valid_i(head1_valid_w),
        .head1_done_i(head1_done_w),
        .head1_data_i(head1_data_w),
        .head1_flags_i(head1_flags_w),
        .head1_exception_i(head1_exception_w),
        .head1_cause_i(head1_cause_w),
        .head1_tval_i(head1_tval_w),
        .head1_device_i(head1_device_w),
        .head1_mem_addr_i(head1_mem_addr_w),
        .head1_mem_data_i(head1_mem_data_w),
        .head1_mem_mask_i(head1_mem_mask_w),
        .wb1_tag_o(wb1_tag_w),
        .wb1_valid_copy_o(wb1_valid_copy_w),
        .wb1_rd_copy_o(wb1_rd_copy_w),
        .wb1_valid_o(wb1_valid_w),
        .wb1_rd_o(wb1_rd_w),
        .wb1_data_o(wb1_data_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w),
        .branch_redirect_valid_i(branch_redirect_valid_w),
        .branch_redirect_tag_i(branch_redirect_tag_w),
        .branch_redirect_pc_i(branch_redirect_pc_w),
        .retire_count_o(retire_count_w),
        .fp_wb_tag_o(fp_wb_tag_w),
        .fp_wb_valid_o(fp_wb_valid_w),
        .fp_wb_rd_o(fp_wb_rd_w),
        .fp_wb_data_o(fp_wb_data_w),
        .commit_lsu_valid_o(commit_lsu_valid_w),
        .commit_lsu_ready_i(commit_lsu_ready_w),
        .commit_lsu_tag_o(commit_lsu_tag_w),
        .commit_lsu_done_valid_i(commit_lsu_done_valid_w),
        .commit_lsu_done_ready_o(commit_lsu_done_ready_w),
        .commit_lsu_done_tag_i(commit_lsu_done_tag_w),
        .commit_lsu_done_error_i(commit_lsu_done_error_w),
        .commit_lsu_done_fault_addr_i(commit_lsu_done_fault_addr_w),
        .commit_lsu_done_data_i(commit_lsu_done_data_w),
        .csr_commit_valid_o(csr_commit_valid_w),
        .fp_commit_flags_valid_o(fp_commit_flags_valid_w),
        .fp_commit_flags_o(fp_commit_flags_w),
        .fp_commit_write_o(fp_commit_write_w),
        .irq_pending_i(irq_pending_w),
        .irq_cause_i(irq_cause_w),
        .irq_wake_i(irq_wake_w),
        .trap_target_i(trap_target_w),
        .csr_mepc_i(csr_mepc_w),
        .mret_valid_o(mret_valid_w),
        .trap_valid_o(trap_valid_w),
        .trap_pc_o(trap_pc_w),
        .trap_cause_o(trap_cause_w),
        .trap_tval_o(trap_tval_w),
        .commit_cancel_valid_o(commit_cancel_valid_w),
        .commit_cancel_tag_o(commit_cancel_tag_w),
        .commit_redirect_valid_o(commit_redirect_valid_w),
        .commit_redirect_pc_o(commit_redirect_pc_w),
        .fetch_stop_o(fetch_stop_w),
        .dc_fence_valid_o(dc_fence_valid_w),
        .dc_fence_ready_i(dc_fence_ready_w),
        .dc_fence_clean_all_o(dc_fence_clean_all_w),
        .dc_fence_done_i(dc_fence_done_w),
        .ic_inv_valid_o(ic_inv_valid_w),
        .ic_inv_ready_i(ic_inv_ready_w),
        .ic_inv_done_i(ic_inv_done_w),
        .counter_retire_count_o(counter_retire_count_w),
        .hpm_branch_count_o(hpm_branch_count_w),
        .trace_valid_o(trace_valid_w[1*ISSUE_WIDTH-1:0]),
        .trace_pc_o(trace_pc_w[32*ISSUE_WIDTH-1:0]),
        .trace_instr_o(trace_instr_w[32*ISSUE_WIDTH-1:0]),
        .trace_rd_o(trace_rd_w[5*ISSUE_WIDTH-1:0]),
        .trace_rd_domain_o(trace_rd_domain_w[2*ISSUE_WIDTH-1:0]),
        .trace_rd_data_o(trace_rd_data_w[64*ISSUE_WIDTH-1:0]),
        .trace_flags_o(trace_flags_w[5*ISSUE_WIDTH-1:0]),
        .trace_mem_valid_o(trace_mem_valid_w[1*ISSUE_WIDTH-1:0]),
        .trace_mem_store_o(trace_mem_store_w[1*ISSUE_WIDTH-1:0]),
        .trace_mem_addr_o(trace_mem_addr_w[32*ISSUE_WIDTH-1:0]),
        .trace_mem_data_o(trace_mem_data_w[64*ISSUE_WIDTH-1:0]),
        .trace_mem_mask_o(trace_mem_mask_w[8*ISSUE_WIDTH-1:0]),
        .trace_trap_o(trace_trap_w),
        .trace_cause_o(trace_cause_w),
        .trace_trap_pc_o(trace_trap_pc_w),
        .trace_tval_o(trace_tval_w),
        .commit_mem_wait_o(commit_mem_wait_w),
        .commit_div_wait_o(commit_div_wait_w),
        .commit_device_wait_o(commit_device_wait_w)
    );

    // csr: frozen per-signal interfaces.
    edrv32_cpu2_csr #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_csr (
        .clk_i(clk_i),
        .rst_n_i(rst_commit_cache_n_w),
        .csr_req_valid_i(csr_req_valid_w),
        .csr_req_ready_o(csr_req_ready_w),
        .csr_req_tag_i(csr_req_tag_w),
        .csr_req_instr_i(csr_req_instr_w),
        .csr_req_src_i(csr_req_src_w),
        .csr_commit_valid_i(csr_commit_valid_w),
        .csr_complete_valid_o(csr_complete_valid_w),
        .csr_complete_ready_i(csr_complete_ready_w),
        .csr_complete_tag_o(csr_complete_tag_w),
        .csr_complete_data_o(csr_complete_data_w),
        .csr_complete_flags_o(csr_complete_flags_w),
        .csr_complete_exception_o(csr_complete_exception_w),
        .csr_complete_cause_o(csr_complete_cause_w),
        .csr_complete_tval_o(csr_complete_tval_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w),
        .fp_commit_flags_valid_i(fp_commit_flags_valid_w),
        .fp_commit_flags_i(fp_commit_flags_w),
        .fp_commit_write_i(fp_commit_write_w),
        .csr_frm_o(csr_frm_w),
        .csr_fs_o(csr_fs_w),
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),
        .mtime_i(mtime_i),
        .irq_pending_o(irq_pending_w),
        .irq_cause_o(irq_cause_w),
        .trap_target_o(trap_target_w),
        .mret_valid_i(mret_valid_w),
        .csr_mepc_o(csr_mepc_w),
        .irq_wake_o(irq_wake_w),
        .trap_valid_i(trap_valid_w),
        .trap_pc_i(trap_pc_w),
        .trap_cause_i(trap_cause_w),
        .trap_tval_i(trap_tval_w),
        .counter_retire_count_i(counter_retire_count_w),
        .hpm_event_i(hpm_event_w),
        .hpm_branch_count_i(hpm_branch_count_w),
        .trace_csr_valid_o(trace_csr_valid_w[1*ISSUE_WIDTH-1:0]),
        .trace_csr_addr_o(trace_csr_addr_w[12*ISSUE_WIDTH-1:0]),
        .trace_csr_data_o(trace_csr_data_w[32*ISSUE_WIDTH-1:0]),
        .trace_fflags_o(trace_fflags_w),
        .trace_frm_o(trace_frm_w),
        .trace_fs_o(trace_fs_w)
    );

    // lsu: frozen per-signal interfaces.
    edrv32_cpu2_lsu #(
        .FPU_FORMAT(FPU_FORMAT)
    ) u_lsu (
        .clk_i(clk_i),
        .rst_n_i(rst_execute_n_w),
        .lsu_req_valid_i(lsu_req_valid_w),
        .lsu_req_ready_o(lsu_req_ready_w),
        .lsu_req_tag_i(lsu_req_tag_w),
        .lsu_req_instr_i(lsu_req_instr_w),
        .lsu_req_addr_i(lsu_req_addr_w),
        .lsu_req_store_data_i(lsu_req_store_data_w),
        .lsu_req_early_i(lsu_req_early_w),
        .early_req_valid_i(early_req_valid_w),
        .early_req_addr_i(early_req_addr_w),
        .early_req_tag_i(early_req_tag_w),
        .early_resp_valid_o(early_resp_valid_w),
        .early_resp_tag_o(early_resp_tag_w),
        .early_resp_hit_o(early_resp_hit_w),
        .early_resp_data_o(early_resp_data_w),
        .lsu_complete_valid_o(lsu_complete_valid_w),
        .lsu_complete_ready_i(lsu_complete_ready_w),
        .lsu_complete_tag_o(lsu_complete_tag_w),
        .lsu_complete_data_o(lsu_complete_data_w),
        .lsu_complete_flags_o(lsu_complete_flags_w),
        .lsu_complete_exception_o(lsu_complete_exception_w),
        .lsu_complete_cause_o(lsu_complete_cause_w),
        .lsu_complete_tval_o(lsu_complete_tval_w),
        .lsu_complete_device_o(lsu_complete_device_w),
        .lsu_complete_mem_addr_o(lsu_complete_mem_addr_w),
        .lsu_complete_mem_data_o(lsu_complete_mem_data_w),
        .lsu_complete_mem_mask_o(lsu_complete_mem_mask_w),
        .commit_lsu_valid_i(commit_lsu_valid_w),
        .commit_lsu_ready_o(commit_lsu_ready_w),
        .commit_lsu_tag_i(commit_lsu_tag_w),
        .commit_lsu_done_valid_o(commit_lsu_done_valid_w),
        .commit_lsu_done_ready_i(commit_lsu_done_ready_w),
        .commit_lsu_done_tag_o(commit_lsu_done_tag_w),
        .commit_lsu_done_error_o(commit_lsu_done_error_w),
        .commit_lsu_done_fault_addr_o(commit_lsu_done_fault_addr_w),
        .commit_lsu_done_data_o(commit_lsu_done_data_w),
        .dc_req_valid_o(dc_req_valid_w),
        .dc_req_ready_i(dc_req_ready_w),
        .dc_req_tag_o(dc_req_tag_w),
        .dc_req_beat_o(dc_req_beat_w),
        .dc_req_addr_o(dc_req_addr_w),
        .dc_req_store_o(dc_req_store_w),
        .dc_req_size_o(dc_req_size_w),
        .dc_req_data_o(dc_req_data_w),
        .dc_req_mask_o(dc_req_mask_w),
        .dc_req_early_o(dc_req_early_w),
        .dc_resp_valid_i(dc_resp_valid_w),
        .dc_resp_ready_o(dc_resp_ready_w),
        .dc_resp_tag_i(dc_resp_tag_w),
        .dc_resp_beat_i(dc_resp_beat_w),
        .dc_resp_way_hit_i(dc_resp_way_hit_w),
        .dc_resp_way0_data_i(dc_resp_way0_data_w),
        .dc_resp_way1_data_i(dc_resp_way1_data_w),
        .dc_resp_error_i(dc_resp_error_w),
        .dc_resp_device_i(dc_resp_device_w),
        .dc_commit_valid_o(dc_commit_valid_w),
        .dc_commit_ready_i(dc_commit_ready_w),
        .dc_commit_tag_o(dc_commit_tag_w),
        .dc_commit_beat_o(dc_commit_beat_w),
        .dc_commit_data_o(dc_commit_data_w),
        .dc_commit_mask_o(dc_commit_mask_w),
        .dc_done_valid_i(dc_done_valid_w),
        .dc_done_ready_o(dc_done_ready_w),
        .dc_done_tag_i(dc_done_tag_w),
        .dc_done_beat_i(dc_done_beat_w),
        .dc_done_error_i(dc_done_error_w),
        .dc_done_data_i(dc_done_data_w),
        .dc_early_valid_o(dc_early_valid_w),
        .dc_early_addr_o(dc_early_addr_w),
        .dc_early_tag_o(dc_early_tag_w),
        .dc_early_resp_valid_i(dc_early_resp_valid_w),
        .dc_early_resp_tag_i(dc_early_resp_tag_w),
        .dc_early_hit_i(dc_early_hit_w),
        .dc_early_way0_data_i(dc_early_way0_data_w),
        .dc_early_way1_data_i(dc_early_way1_data_w),
        .age_head_i(age_head_w),
        .cancel_valid_i(cancel_valid_w),
        .cancel_tag_i(cancel_tag_w),
        .dc_cancel_valid_o(dc_cancel_valid_w),
        .dc_cancel_tag_o(dc_cancel_tag_w),
        .dc_age_head_o(dc_age_head_w)
    );

    // icache: frozen per-signal interfaces.
    edrv32_cpu2_icache #(
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_icache (
        .clk_i(clk_i),
        .rst_n_i(rst_frontend_n_w),
        .ic_req_valid_i(ic_req_valid_w),
        .ic_req_ready_o(ic_req_ready_w),
        .ic_req_addr_i(ic_req_addr_w),
        .ic_resp_valid_o(ic_resp_valid_w),
        .ic_resp_ready_i(ic_resp_ready_w),
        .ic_resp_bank0_way0_instr_o(ic_resp_bank0_way0_instr_w),
        .ic_resp_bank0_way1_instr_o(ic_resp_bank0_way1_instr_w),
        .ic_resp_bank1_way0_instr_o(ic_resp_bank1_way0_instr_w),
        .ic_resp_bank1_way1_instr_o(ic_resp_bank1_way1_instr_w),
        .ic_resp_bank0_way_hit_o(ic_resp_bank0_way_hit_w),
        .ic_resp_bank0_error_o(ic_resp_bank0_error_w),
        .ic_resp_bank1_way_hit_o(ic_resp_bank1_way_hit_w),
        .ic_resp_bank1_error_o(ic_resp_bank1_error_w),
        .axi_arid_o(ic_axi_arid_o),
        .axi_araddr_o(ic_axi_araddr_o),
        .axi_arlen_o(ic_axi_arlen_o),
        .axi_arsize_o(ic_axi_arsize_o),
        .axi_arburst_o(ic_axi_arburst_o),
        .axi_arvalid_o(ic_axi_arvalid_o),
        .axi_arready_i(ic_axi_arready_i),
        .axi_rid_i(ic_axi_rid_i),
        .axi_rdata_i(ic_axi_rdata_i),
        .axi_rresp_i(ic_axi_rresp_i),
        .axi_rlast_i(ic_axi_rlast_i),
        .axi_rvalid_i(ic_axi_rvalid_i),
        .axi_rready_o(ic_axi_rready_o),
        .ic_cancel_i(ic_cancel_w),
        .ic_inv_valid_i(ic_inv_valid_w),
        .ic_inv_ready_o(ic_inv_ready_w),
        .ic_inv_done_o(ic_inv_done_w),
        .ic_miss_event_o(ic_miss_event_w),
        .debug_miss_o(icache_debug_miss_w)
    );

    // dcache: frozen per-signal interfaces.
    edrv32_cpu2_dcache #(
        .FPU_FORMAT(FPU_FORMAT)
    ) u_dcache (
        .clk_i(clk_i),
        .rst_n_i(rst_commit_cache_n_w),
        .dc_req_valid_i(dc_req_valid_w),
        .dc_req_ready_o(dc_req_ready_w),
        .dc_req_tag_i(dc_req_tag_w),
        .dc_req_beat_i(dc_req_beat_w),
        .dc_req_addr_i(dc_req_addr_w),
        .dc_req_store_i(dc_req_store_w),
        .dc_req_size_i(dc_req_size_w),
        .dc_req_data_i(dc_req_data_w),
        .dc_req_mask_i(dc_req_mask_w),
        .dc_req_early_i(dc_req_early_w),
        .dc_resp_valid_o(dc_resp_valid_w),
        .dc_resp_ready_i(dc_resp_ready_w),
        .dc_resp_tag_o(dc_resp_tag_w),
        .dc_resp_beat_o(dc_resp_beat_w),
        .dc_resp_way_hit_o(dc_resp_way_hit_w),
        .dc_resp_way0_data_o(dc_resp_way0_data_w),
        .dc_resp_way1_data_o(dc_resp_way1_data_w),
        .dc_resp_error_o(dc_resp_error_w),
        .dc_resp_device_o(dc_resp_device_w),
        .dc_commit_valid_i(dc_commit_valid_w),
        .dc_commit_ready_o(dc_commit_ready_w),
        .dc_commit_tag_i(dc_commit_tag_w),
        .dc_commit_beat_i(dc_commit_beat_w),
        .dc_commit_data_i(dc_commit_data_w),
        .dc_commit_mask_i(dc_commit_mask_w),
        .dc_done_valid_o(dc_done_valid_w),
        .dc_done_ready_i(dc_done_ready_w),
        .dc_done_tag_o(dc_done_tag_w),
        .dc_done_beat_o(dc_done_beat_w),
        .dc_done_error_o(dc_done_error_w),
        .dc_done_data_o(dc_done_data_w),
        .dc_early_valid_i(dc_early_valid_w),
        .dc_early_addr_i(dc_early_addr_w),
        .dc_early_tag_i(dc_early_tag_w),
        .dc_early_resp_valid_o(dc_early_resp_valid_w),
        .dc_early_resp_tag_o(dc_early_resp_tag_w),
        .dc_early_hit_o(dc_early_hit_w),
        .dc_early_way0_data_o(dc_early_way0_data_w),
        .dc_early_way1_data_o(dc_early_way1_data_w),
        .axi_arid_o(dc_axi_arid_o),
        .axi_araddr_o(dc_axi_araddr_o),
        .axi_arlen_o(dc_axi_arlen_o),
        .axi_arsize_o(dc_axi_arsize_o),
        .axi_arburst_o(dc_axi_arburst_o),
        .axi_arvalid_o(dc_axi_arvalid_o),
        .axi_arready_i(dc_axi_arready_i),
        .axi_rid_i(dc_axi_rid_i),
        .axi_rdata_i(dc_axi_rdata_i),
        .axi_rresp_i(dc_axi_rresp_i),
        .axi_rlast_i(dc_axi_rlast_i),
        .axi_rvalid_i(dc_axi_rvalid_i),
        .axi_rready_o(dc_axi_rready_o),
        .axi_awid_o(dc_axi_awid_o),
        .axi_awaddr_o(dc_axi_awaddr_o),
        .axi_awlen_o(dc_axi_awlen_o),
        .axi_awsize_o(dc_axi_awsize_o),
        .axi_awburst_o(dc_axi_awburst_o),
        .axi_awvalid_o(dc_axi_awvalid_o),
        .axi_awready_i(dc_axi_awready_i),
        .axi_wdata_o(dc_axi_wdata_o),
        .axi_wstrb_o(dc_axi_wstrb_o),
        .axi_wlast_o(dc_axi_wlast_o),
        .axi_wvalid_o(dc_axi_wvalid_o),
        .axi_wready_i(dc_axi_wready_i),
        .axi_bid_i(dc_axi_bid_i),
        .axi_bresp_i(dc_axi_bresp_i),
        .axi_bvalid_i(dc_axi_bvalid_i),
        .axi_bready_o(dc_axi_bready_o),
        .dc_cancel_valid_i(dc_cancel_valid_w),
        .dc_cancel_tag_i(dc_cancel_tag_w),
        .dc_age_head_i(dc_age_head_w),
        .dc_fence_valid_i(dc_fence_valid_w),
        .dc_fence_ready_o(dc_fence_ready_w),
        .dc_fence_clean_all_i(dc_fence_clean_all_w),
        .dc_fence_done_o(dc_fence_done_w),
        .maint_req_valid_i(maint_req_valid_w),
        .maint_req_ready_o(maint_req_ready_w),
        .maint_cmd_i(maint_cmd_w),
        .maint_addr_i(maint_addr_w),
        .maint_size_i(maint_size_w),
        .maint_busy_o(maint_busy_w),
        .wb_err_o(wb_err_w),
        .wb_err_addr_o(wb_err_addr_w),
        .dc_wb_event_o(dc_wb_event_w),
        .dc_miss_event_o(dc_miss_event_w),
        .trace_mem_effect_valid_o(trace_mem_effect_valid_w),
        .trace_mem_effect_tag_o(trace_mem_effect_tag_w),
        .trace_mem_effect_addr_o(trace_mem_effect_addr_w),
        .trace_mem_effect_data_o(trace_mem_effect_data_w),
        .trace_mem_effect_mask_o(trace_mem_effect_mask_w),
        .debug_miss_o(dcache_debug_miss_w)
    );

    // cache_ctrl: frozen per-signal interfaces.
    edrv32_cpu2_cache_ctrl u_cache_ctrl (
        .clk_i(clk_i),
        .rst_n_i(rst_commit_cache_n_w),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .maint_req_valid_o(maint_req_valid_w),
        .maint_req_ready_i(maint_req_ready_w),
        .maint_cmd_o(maint_cmd_w),
        .maint_addr_o(maint_addr_w),
        .maint_size_o(maint_size_w),
        .maint_busy_i(maint_busy_w),
        .wb_err_i(wb_err_w),
        .wb_err_addr_i(wb_err_addr_w),
        .cache_irq_o(cache_irq_o)
    );
    generate
        if (ISSUE_WIDTH == 1) begin : g_trace_pad
            assign trace_valid_w[1:1] = 1'b0;
            assign trace_pc_w[63:32] = 32'b0;
            assign trace_instr_w[63:32] = 32'b0;
            assign trace_rd_w[9:5] = 5'b0;
            assign trace_rd_domain_w[3:2] = 2'b0;
            assign trace_rd_data_w[127:64] = 64'b0;
            assign trace_flags_w[9:5] = 5'b0;
            assign trace_mem_valid_w[1:1] = 1'b0;
            assign trace_mem_store_w[1:1] = 1'b0;
            assign trace_mem_addr_w[63:32] = 32'b0;
            assign trace_mem_data_w[127:64] = 64'b0;
            assign trace_mem_mask_w[15:8] = 8'b0;
            assign trace_csr_valid_w[1:1] = 1'b0;
            assign trace_csr_addr_w[23:12] = 12'b0;
            assign trace_csr_data_w[63:32] = 32'b0;
        end
    endgenerate
    wire trace_redirect_valid_w;
    wire [T-1:0] trace_redirect_tag_w;
    wire [31:0] trace_redirect_pc_w;
    wire [31:0] trace_redirect_target_w;
    wire [1:0] trace_redirect_stage_w;
    wire [1:0] trace_redirect_cause_w;
    assign trace_redirect_valid_w = branch_redirect_valid_w || f2_redirect_valid_w;
    assign trace_redirect_tag_w = branch_redirect_valid_w ? branch_redirect_tag_w : {T{1'b0}};
    assign trace_redirect_pc_w = branch_redirect_valid_w ? trace_branch_pc_w : f2_redirect_pc_w;
    assign trace_redirect_target_w = branch_redirect_valid_w ? branch_redirect_pc_w :
        f2_redirect_target_w;
    assign trace_redirect_stage_w = branch_redirect_valid_w ? trace_branch_stage_w : 2'd1;
    assign trace_redirect_cause_w = branch_redirect_valid_w ? trace_branch_cause_w :
        f2_redirect_cause_w;
    wire trace_source0_valid_w;
    assign trace_source0_valid_w = source0_valid_w;
    wire [T-1:0] trace_source0_tag_w;
    assign trace_source0_tag_w = source0_tag_w;
    wire trace_source0_domain_w;
    assign trace_source0_domain_w = source0_domain_w;
    wire trace_source1_valid_w;
    assign trace_source1_valid_w = source1_valid_w;
    wire [T-1:0] trace_source1_tag_w;
    assign trace_source1_tag_w = source1_tag_w;
    wire trace_source1_domain_w;
    assign trace_source1_domain_w = source1_domain_w;
    wire trace_source2_valid_w;
    assign trace_source2_valid_w = source2_valid_w;
    wire [T-1:0] trace_source2_tag_w;
    assign trace_source2_tag_w = source2_tag_w;
    wire trace_source2_domain_w;
    assign trace_source2_domain_w = source2_domain_w;
    wire trace_source3_valid_w;
    assign trace_source3_valid_w = source3_valid_w;
    wire [T-1:0] trace_source3_tag_w;
    assign trace_source3_tag_w = source3_tag_w;
    wire trace_source3_domain_w;
    assign trace_source3_domain_w = source3_domain_w;
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w;
    assign unused_w = ^{
        ib_credit_w,
        fp_resp_valid_w,
        fp_resp_ready_w,
        fp_resp_tag_w,
        fp_resp_data_w,
        fp_read0_addr_w,
        fp_read0_data_w,
        fp_read1_addr_w,
        fp_read1_data_w,
        fp_read2_addr_w,
        fp_read2_data_w,
        fp_wb_valid_w,
        fp_wb_rd_w,
        fp_wb_data_w,
        fp_wb_tag_w,
        fp_req_ready_w,
        fp_req_valid_w,
        fp_req_tag_w,
        fp_req_instr_w,
        fp_req_src1_w,
        fp_req_src2_w,
        fp_req_src3_w,
        fp_req_int_src_w,
        fp_req_rm_w,
        trace_branch_pc_w,
        trace_branch_stage_w,
        trace_branch_cause_w,
        fp_resp_flags_w,
        fp_resp_int_dest_w,
        fp_commit_flags_valid_w,
        fp_commit_flags_w,
        fp_commit_write_w,
        trace_valid_w,
        trace_pc_w,
        trace_instr_w,
        trace_rd_w,
        trace_rd_domain_w,
        trace_rd_data_w,
        trace_flags_w,
        trace_mem_valid_w,
        trace_mem_store_w,
        trace_mem_addr_w,
        trace_mem_data_w,
        trace_mem_mask_w,
        trace_trap_w,
        trace_cause_w,
        trace_trap_pc_w,
        trace_tval_w,
        trace_csr_valid_w,
        trace_csr_addr_w,
        trace_csr_data_w,
        trace_fflags_w,
        trace_frm_w,
        trace_fs_w,
        early_resp_valid_w,
        early_resp_tag_w,
        early_resp_hit_w,
        early_resp_data_w,
        ic_miss_event_w,
        dc_wb_event_w,
        dc_miss_event_w,
        trace_mem_effect_valid_w,
        trace_mem_effect_tag_w,
        trace_mem_effect_addr_w,
        trace_mem_effect_data_w,
        trace_mem_effect_mask_w,
        trace_redirect_valid_w,
        trace_redirect_tag_w,
        trace_redirect_pc_w,
        trace_redirect_target_w,
        trace_redirect_stage_w,
        trace_redirect_cause_w,
        trace_source0_valid_w,
        trace_source0_tag_w,
        trace_source0_domain_w,
        trace_source1_valid_w,
        trace_source1_tag_w,
        trace_source1_domain_w,
        trace_source2_valid_w,
        trace_source2_tag_w,
        trace_source2_domain_w,
        trace_source3_valid_w,
        trace_source3_tag_w,
        trace_source3_domain_w
    };
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
