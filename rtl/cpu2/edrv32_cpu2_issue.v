// File: edrv32_cpu2_issue.v
// Spec: cpu-v2-spec 2.3, 3.2-3.6, 5.1-5.3, 5.6; interface-freeze implementation supplements.
// Description: Program-order allocation, pipeline mapping, two-domain tag scoreboard and
// local registered source/dispatch records; channel encodings 0/1 EX,2 MUL,3 DIV,4 LSU,5 CSR,6 FP,7 trap.
// Clock domain: clk_sys.
module edrv32_cpu2_issue #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Accepted results also capture sources at the ID/EX allocation edge.
    input wire alu0_complete_valid_i,
    input wire alu0_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu0_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_i,
    input wire alu1_complete_valid_i,
    input wire alu1_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu1_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_i,
    input wire branch_complete_valid_i,
    input wire branch_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_i,
    input wire mul_complete_valid_i,
    input wire mul_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] mul_complete_data_i,
    input wire div_complete_valid_i,
    input wire div_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] div_complete_data_i,
    // Registered LSU early response; never used in ID qualification.
    input wire early_resp_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] early_resp_tag_i,
    input wire early_resp_hit_i,
    input wire [31:0] early_resp_data_i,
    input wire lsu_complete_valid_i,
    input wire lsu_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_complete_data_i,
    input wire csr_complete_valid_i,
    input wire csr_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] csr_complete_data_i,
    input wire fp_resp_valid_i,
    input wire fp_resp_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_resp_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_resp_data_i,
    // IB heads, architectural RF, shared completion sources, and registered execution entries.
    input wire lsu_complete_device_i,
    input wire clk_i,
    input wire rst_n_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i,
    input wire [2-1:0] csr_fs_i,
    input wire [3-1:0] csr_frm_i,
    input wire ib_head0_valid_i,
    input wire [32-1:0] ib_head0_pc_i,
    input wire [32-1:0] ib_head0_instr_i,
    input wire ib_head0_error_i,
    input wire [5-1:0] ib_head0_candidates_i,
    input wire ib_head0_predict_taken_i,
    input wire [32-1:0] ib_head0_predict_target_i,
    input wire ib_head0_predict_token_i,
    input wire [3-1:0] ib_head0_predict_provider_i,
    input wire ib_head0_predict_alternate_i,
    input wire [9-1:0] ib_head0_predict_index0_i,
    input wire [9-1:0] ib_head0_predict_index1_i,
    input wire [9-1:0] ib_head0_predict_index2_i,
    input wire [9-1:0] ib_head0_predict_index3_i,
    input wire [10-1:0] ib_head0_predict_tag0_i,
    input wire [10-1:0] ib_head0_predict_tag1_i,
    input wire [10-1:0] ib_head0_predict_tag2_i,
    input wire [10-1:0] ib_head0_predict_tag3_i,
    input wire [12-1:0] ib_head0_predict_base_index_i,
    input wire [12-1:0] ib_head0_predict_fast_index_i,
    input wire [(128*ISSUE_WIDTH)-1:0] ib_head0_ras_data_i,
    input wire [(ISSUE_WIDTH+1)-1:0] ib_head0_ras_ptr_i,
    input wire [(ISSUE_WIDTH+2)-1:0] ib_head0_ras_count_i,
    input wire ib_head1_valid_i,
    input wire [32-1:0] ib_head1_pc_i,
    input wire [32-1:0] ib_head1_instr_i,
    input wire ib_head1_error_i,
    input wire [5-1:0] ib_head1_candidates_i,
    input wire ib_head1_predict_taken_i,
    input wire [32-1:0] ib_head1_predict_target_i,
    input wire ib_head1_predict_token_i,
    input wire [3-1:0] ib_head1_predict_provider_i,
    input wire ib_head1_predict_alternate_i,
    input wire [9-1:0] ib_head1_predict_index0_i,
    input wire [9-1:0] ib_head1_predict_index1_i,
    input wire [9-1:0] ib_head1_predict_index2_i,
    input wire [9-1:0] ib_head1_predict_index3_i,
    input wire [10-1:0] ib_head1_predict_tag0_i,
    input wire [10-1:0] ib_head1_predict_tag1_i,
    input wire [10-1:0] ib_head1_predict_tag2_i,
    input wire [10-1:0] ib_head1_predict_tag3_i,
    input wire [12-1:0] ib_head1_predict_base_index_i,
    input wire [12-1:0] ib_head1_predict_fast_index_i,
    input wire [(128*ISSUE_WIDTH)-1:0] ib_head1_ras_data_i,
    input wire [(ISSUE_WIDTH+1)-1:0] ib_head1_ras_ptr_i,
    input wire [(ISSUE_WIDTH+2)-1:0] ib_head1_ras_count_i,
    output wire [2-1:0] ib_remove_count_o,
    output wire [5-1:0] id_rs0_o,
    output wire id_owner0_o,
    input wire [32-1:0] id_data0_i,
    output wire [5-1:0] id_rs1_o,
    output wire id_owner1_o,
    input wire [32-1:0] id_data1_i,
    output wire [5-1:0] id_rs2_o,
    output wire id_owner2_o,
    input wire [32-1:0] id_data2_i,
    output wire [5-1:0] id_rs3_o,
    output wire id_owner3_o,
    input wire [32-1:0] id_data3_i,
    input wire wb0_valid_i,
    input wire [5-1:0] wb0_rd_i,
    input wire [32-1:0] wb0_data_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] wb0_tag_i,
    input wire wb1_valid_i,
    input wire [5-1:0] wb1_rd_i,
    input wire [32-1:0] wb1_data_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] wb1_tag_i,
    output wire [5-1:0] fp_read0_addr_o,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read0_data_i,
    output wire [5-1:0] fp_read1_addr_o,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read1_data_i,
    output wire [5-1:0] fp_read2_addr_o,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read2_data_i,
    input wire fp_wb_valid_i,
    input wire [5-1:0] fp_wb_rd_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_wb_data_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_wb_tag_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?5:4)-1:0] allocate_credit_i,
    input wire allocate_ready_i,
    output wire allocate_valid_o,
    output wire [2-1:0] allocate_count_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] allocate0_tag_o,
    output wire [32-1:0] allocate0_pc_o,
    output wire [32-1:0] allocate0_instr_o,
    output wire [5-1:0] allocate0_rd_o,
    output wire [2-1:0] allocate0_dest_o,
    output wire [32-1:0] allocate0_csr_src_o,
    output wire allocate0_store_o,
    output wire allocate0_divide_o,
    output wire allocate0_double_beat_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] allocate1_tag_o,
    output wire [32-1:0] allocate1_pc_o,
    output wire [32-1:0] allocate1_instr_o,
    output wire [5-1:0] allocate1_rd_o,
    output wire [2-1:0] allocate1_dest_o,
    output wire [32-1:0] allocate1_csr_src_o,
    output wire allocate1_store_o,
    output wire allocate1_divide_o,
    output wire allocate1_double_beat_o,
    output wire source0_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source0_tag_o,
    output wire source0_domain_o,
    input wire source0_ready_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source0_data_i,
    output wire source1_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source1_tag_o,
    output wire source1_domain_o,
    input wire source1_ready_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source1_data_i,
    output wire source2_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source2_tag_o,
    output wire source2_domain_o,
    input wire source2_ready_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source2_data_i,
    output wire source3_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source3_tag_o,
    output wire source3_domain_o,
    input wire source3_ready_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source3_data_i,
    output wire source4_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source4_tag_o,
    output wire source4_domain_o,
    input wire source4_ready_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source4_data_i,
    input wire execute0_ready_i,
    output wire execute0_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_tag_o,
    output wire [32-1:0] execute0_pc_o,
    output wire [32-1:0] execute0_instr_o,
    output wire [32-1:0] execute0_src1_o,
    output wire [32-1:0] execute0_src2_o,
    output wire [32-1:0] execute0_imm_o,
    output wire execute0_late_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source1_tag_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source2_tag_o,
    output wire execute0_source1_wait_o,
    output wire execute0_source2_wait_o,
    output wire execute0_predict_taken_o,
    output wire [32-1:0] execute0_predict_target_o,
    output wire execute0_predict_token_o,
    output wire [3-1:0] execute0_predict_provider_o,
    output wire execute0_predict_alternate_o,
    output wire [9-1:0] execute0_predict_index0_o,
    output wire [9-1:0] execute0_predict_index1_o,
    output wire [9-1:0] execute0_predict_index2_o,
    output wire [9-1:0] execute0_predict_index3_o,
    output wire [10-1:0] execute0_predict_tag0_o,
    output wire [10-1:0] execute0_predict_tag1_o,
    output wire [10-1:0] execute0_predict_tag2_o,
    output wire [10-1:0] execute0_predict_tag3_o,
    output wire [12-1:0] execute0_predict_base_index_o,
    output wire [12-1:0] execute0_predict_fast_index_o,
    output wire [(128*ISSUE_WIDTH)-1:0] execute0_ras_data_o,
    output wire [(ISSUE_WIDTH+1)-1:0] execute0_ras_ptr_o,
    output wire [(ISSUE_WIDTH+2)-1:0] execute0_ras_count_o,
    input wire execute1_ready_i,
    output wire execute1_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_tag_o,
    output wire [32-1:0] execute1_pc_o,
    output wire [32-1:0] execute1_instr_o,
    output wire [32-1:0] execute1_src1_o,
    output wire [32-1:0] execute1_src2_o,
    output wire [32-1:0] execute1_imm_o,
    output wire execute1_late_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source1_tag_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source2_tag_o,
    output wire execute1_source1_wait_o,
    output wire execute1_source2_wait_o,
    output wire execute1_predict_taken_o,
    output wire [32-1:0] execute1_predict_target_o,
    output wire execute1_predict_token_o,
    output wire [3-1:0] execute1_predict_provider_o,
    output wire execute1_predict_alternate_o,
    output wire [9-1:0] execute1_predict_index0_o,
    output wire [9-1:0] execute1_predict_index1_o,
    output wire [9-1:0] execute1_predict_index2_o,
    output wire [9-1:0] execute1_predict_index3_o,
    output wire [10-1:0] execute1_predict_tag0_o,
    output wire [10-1:0] execute1_predict_tag1_o,
    output wire [10-1:0] execute1_predict_tag2_o,
    output wire [10-1:0] execute1_predict_tag3_o,
    output wire [12-1:0] execute1_predict_base_index_o,
    output wire [12-1:0] execute1_predict_fast_index_o,
    output wire [(128*ISSUE_WIDTH)-1:0] execute1_ras_data_o,
    output wire [(ISSUE_WIDTH+1)-1:0] execute1_ras_ptr_o,
    output wire [(ISSUE_WIDTH+2)-1:0] execute1_ras_count_o,
    input wire mul_req_ready_i,
    output wire mul_req_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_req_tag_o,
    output wire [32-1:0] mul_req_instr_o,
    output wire [32-1:0] mul_req_src1_o,
    output wire [32-1:0] mul_req_src2_o,
    input wire div_req_ready_i,
    output wire div_req_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_req_tag_o,
    output wire [32-1:0] div_req_instr_o,
    output wire [32-1:0] div_req_src1_o,
    output wire [32-1:0] div_req_src2_o,
    input wire lsu_req_ready_i,
    output wire lsu_req_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_req_tag_o,
    output wire [32-1:0] lsu_req_instr_o,
    output wire [32-1:0] lsu_req_addr_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_req_store_data_o,
    output wire lsu_req_early_o,
    input wire csr_req_ready_i,
    output wire csr_req_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_req_tag_o,
    output wire [32-1:0] csr_req_instr_o,
    output wire [32-1:0] csr_req_src_o,
    input wire fp_req_ready_i,
    output wire fp_req_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_req_tag_o,
    output wire [32-1:0] fp_req_instr_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src1_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src2_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src3_o,
    output wire [32-1:0] fp_req_int_src_o,
    output wire [3-1:0] fp_req_rm_o,
    output wire early_req_valid_o,
    output wire [32-1:0] early_req_addr_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] early_req_tag_o,
    input wire decode_complete_ready_i,
    output wire decode_complete_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] decode_complete_tag_o,
    output wire decode_complete_exception_o,
    output wire [4-1:0] decode_complete_cause_o,
    output wire [32-1:0] decode_complete_tval_o,
    output wire predict_read0_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] predict_read0_tag_o,
    output wire [9-1:0] predict_read0_index0_o,
    output wire [9-1:0] predict_read0_index1_o,
    output wire [9-1:0] predict_read0_index2_o,
    output wire [9-1:0] predict_read0_index3_o,
    output wire [10-1:0] predict_read0_tag0_o,
    output wire [10-1:0] predict_read0_tag1_o,
    output wire [10-1:0] predict_read0_tag2_o,
    output wire [10-1:0] predict_read0_tag3_o,
    output wire [12-1:0] predict_read0_base_index_o,
    output wire predict_read1_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] predict_read1_tag_o,
    output wire [9-1:0] predict_read1_index0_o,
    output wire [9-1:0] predict_read1_index1_o,
    output wire [9-1:0] predict_read1_index2_o,
    output wire [9-1:0] predict_read1_index3_o,
    output wire [10-1:0] predict_read1_tag0_o,
    output wire [10-1:0] predict_read1_tag1_o,
    output wire [10-1:0] predict_read1_tag2_o,
    output wire [10-1:0] predict_read1_tag3_o,
    output wire [12-1:0] predict_read1_base_index_o,
    // I06: frozen HPM/debug observation.
    output wire [7:0] issue_hpm_o,
    output reg [2:0] issue_pair_cause_o,
    output reg issue_wait_o
);
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam N = 2**T;
    localparam [T:0] N_COUNT = N;
    localparam B = FPU_FORMAT=="FD" ? 64 : 32;
    localparam R = FPU_FORMAT=="F" ? 3 : FPU_FORMAT=="FD" ? 2 : 0;
    localparam S = FPU_FORMAT=="F" ? ISSUE_WIDTH*2+1 : ISSUE_WIDTH*2;
    reg [T-1:0] tail_r;
    wire [T-1:0] tag0_w = tail_r;
    wire [T-1:0] tag1_w = tail_r + 1'b1;
    wire [T-1:0] cancel_age_w = cancel_tag_i-age_head_i;
    wire fire_w = allocate_valid_o && allocate_ready_i;
    wire [N-1:0] serial_pending_w;
    wire [3-1:0] d0_class_w;
    wire [5-1:0] d0_rs1_w;
    wire [5-1:0] d0_rs2_w;
    wire [5-1:0] d0_rs3_w;
    wire d0_rs1_used_w;
    wire d0_rs2_used_w;
    wire d0_rs3_used_w;
    wire d0_rs1_domain_w;
    wire d0_rs2_domain_w;
    wire d0_rs3_domain_w;
    wire [5-1:0] d0_rd_w;
    wire [2-1:0] d0_dest_w;
    wire [32-1:0] d0_imm_w;
    wire d0_load_w;
    wire d0_store_w;
    wire d0_double_beat_w;
    wire d0_late_supported_w;
    wire [3-1:0] d0_rm_w;
    wire d0_exception_w;
    wire [4-1:0] d0_cause_w;
    wire [32-1:0] d0_tval_w;
    edrv32_cpu2_decode #(.FPU_FORMAT(FPU_FORMAT)) u_decode0 (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .instr_i(ib_head0_instr_i),
        .pc_i(ib_head0_pc_i),
        .error_i(ib_head0_error_i),
        .csr_fs_i(csr_fs_i),
        .csr_frm_i(csr_frm_i),
        .class_o(d0_class_w),
        .rs1_o(d0_rs1_w),
        .rs2_o(d0_rs2_w),
        .rs3_o(d0_rs3_w),
        .rs1_used_o(d0_rs1_used_w),
        .rs2_used_o(d0_rs2_used_w),
        .rs3_used_o(d0_rs3_used_w),
        .rs1_domain_o(d0_rs1_domain_w),
        .rs2_domain_o(d0_rs2_domain_w),
        .rs3_domain_o(d0_rs3_domain_w),
        .rd_o(d0_rd_w),
        .dest_o(d0_dest_w),
        .imm_o(d0_imm_w),
        .load_o(d0_load_w),
        .store_o(d0_store_w),
        .double_beat_o(d0_double_beat_w),
        .late_supported_o(d0_late_supported_w),
        .rm_o(d0_rm_w),
        .exception_o(d0_exception_w),
        .cause_o(d0_cause_w),
        .tval_o(d0_tval_w)
    );
    assign id_rs0_o = (ISSUE_WIDTH > 0) ? d0_rs1_w : 5'd0;
    assign id_owner0_o = (ISSUE_WIDTH == 2) &&
        (ib_head0_candidates_i[4] ? ib_head0_candidates_i[2] :
        ib_head0_candidates_i[0]);
    assign id_rs1_o = (ISSUE_WIDTH > 0) ? d0_rs2_w : 5'd0;
    assign id_owner1_o = (ISSUE_WIDTH == 2) &&
        (ib_head0_candidates_i[4] ? ib_head0_candidates_i[3] :
        ib_head0_candidates_i[1]);
    wire [3-1:0] d1_class_w;
    wire [5-1:0] d1_rs1_w;
    wire [5-1:0] d1_rs2_w;
    wire [5-1:0] d1_rs3_w;
    wire d1_rs1_used_w;
    wire d1_rs2_used_w;
    wire d1_rs3_used_w;
    wire d1_rs1_domain_w;
    wire d1_rs2_domain_w;
    wire d1_rs3_domain_w;
    wire [5-1:0] d1_rd_w;
    wire [2-1:0] d1_dest_w;
    wire [32-1:0] d1_imm_w;
    wire d1_load_w;
    wire d1_store_w;
    wire d1_double_beat_w;
    wire d1_late_supported_w;
    wire [3-1:0] d1_rm_w;
    wire d1_exception_w;
    wire [4-1:0] d1_cause_w;
    wire [32-1:0] d1_tval_w;
    generate
        if (ISSUE_WIDTH == 2) begin : g_second_decode
            edrv32_cpu2_decode #(.FPU_FORMAT(FPU_FORMAT)) u_decode1 (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .instr_i(ib_head1_instr_i),
                .pc_i(ib_head1_pc_i),
                .error_i(ib_head1_error_i),
                .csr_fs_i(csr_fs_i),
                .csr_frm_i(csr_frm_i),
                .class_o(d1_class_w),
                .rs1_o(d1_rs1_w),
                .rs2_o(d1_rs2_w),
                .rs3_o(d1_rs3_w),
                .rs1_used_o(d1_rs1_used_w),
                .rs2_used_o(d1_rs2_used_w),
                .rs3_used_o(d1_rs3_used_w),
                .rs1_domain_o(d1_rs1_domain_w),
                .rs2_domain_o(d1_rs2_domain_w),
                .rs3_domain_o(d1_rs3_domain_w),
                .rd_o(d1_rd_w),
                .dest_o(d1_dest_w),
                .imm_o(d1_imm_w),
                .load_o(d1_load_w),
                .store_o(d1_store_w),
                .double_beat_o(d1_double_beat_w),
                .late_supported_o(d1_late_supported_w),
                .rm_o(d1_rm_w),
                .exception_o(d1_exception_w),
                .cause_o(d1_cause_w),
                .tval_o(d1_tval_w)
            );
        end else begin : g_no_second_decode
            assign d1_class_w = {3{1'b0}};
            assign d1_rs1_w = {5{1'b0}};
            assign d1_rs2_w = {5{1'b0}};
            assign d1_rs3_w = {5{1'b0}};
            assign d1_rs1_used_w = 1'b0;
            assign d1_rs2_used_w = 1'b0;
            assign d1_rs3_used_w = 1'b0;
            assign d1_rs1_domain_w = 1'b0;
            assign d1_rs2_domain_w = 1'b0;
            assign d1_rs3_domain_w = 1'b0;
            assign d1_rd_w = {5{1'b0}};
            assign d1_dest_w = {2{1'b0}};
            assign d1_imm_w = {32{1'b0}};
            assign d1_load_w = 1'b0;
            assign d1_store_w = 1'b0;
            assign d1_double_beat_w = 1'b0;
            assign d1_late_supported_w = 1'b0;
            assign d1_rm_w = {3{1'b0}};
            assign d1_exception_w = 1'b0;
            assign d1_cause_w = {4{1'b0}};
            assign d1_tval_w = {32{1'b0}};
        end
    endgenerate
    assign id_rs2_o = (ISSUE_WIDTH > 1) ? d1_rs1_w : 5'd0;
    assign id_owner2_o = (ISSUE_WIDTH == 2) &&
        (ib_head1_candidates_i[4] ? ib_head1_candidates_i[2] :
        ib_head1_candidates_i[0]);
    assign id_rs3_o = (ISSUE_WIDTH > 1) ? d1_rs2_w : 5'd0;
    assign id_owner3_o = (ISSUE_WIDTH == 2) &&
        (ib_head1_candidates_i[4] ? ib_head1_candidates_i[3] :
        ib_head1_candidates_i[1]);
    wire [32-1:0] entry_pc_w [0:N-1];
    wire [32-1:0] entry_instr_w [0:N-1];
    wire [5-1:0] entry_rd_w [0:N-1];
    wire [2-1:0] entry_dest_w [0:N-1];
    wire [3-1:0] entry_class_w [0:N-1];
    wire [3-1:0] entry_channel_w [0:N-1];
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] entry_src1_w [0:N-1];
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] entry_src2_w [0:N-1];
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] entry_src3_w [0:N-1];
    wire [32-1:0] entry_imm_w [0:N-1];
    wire entry_late_w [0:N-1];
    wire [T-1:0] entry_source1_tag_w [0:N-1];
    wire [T-1:0] entry_source2_tag_w [0:N-1];
    wire entry_dispatch_ready_w [0:N-1];
    wire entry_source1_wait_w [0:N-1];
    wire entry_source2_wait_w [0:N-1];
    wire entry_early_w [0:N-1];
    wire [3-1:0] entry_rm_w [0:N-1];
    wire [4-1:0] entry_cause_w [0:N-1];
    wire [32-1:0] entry_tval_w [0:N-1];
    wire entry_predict_taken_w [0:N-1];
    wire [32-1:0] entry_predict_target_w [0:N-1];
    wire entry_predict_token_w [0:N-1];
    wire [3-1:0] entry_predict_provider_w [0:N-1];
    wire entry_predict_alternate_w [0:N-1];
    wire [9-1:0] entry_predict_index0_w [0:N-1];
    wire [9-1:0] entry_predict_index1_w [0:N-1];
    wire [9-1:0] entry_predict_index2_w [0:N-1];
    wire [9-1:0] entry_predict_index3_w [0:N-1];
    wire [10-1:0] entry_predict_tag0_w [0:N-1];
    wire [10-1:0] entry_predict_tag1_w [0:N-1];
    wire [10-1:0] entry_predict_tag2_w [0:N-1];
    wire [10-1:0] entry_predict_tag3_w [0:N-1];
    wire [12-1:0] entry_predict_base_index_w [0:N-1];
    wire [12-1:0] entry_predict_fast_index_w [0:N-1];
    wire [(128*ISSUE_WIDTH)-1:0] entry_ras_data_w [0:N-1];
    wire [(ISSUE_WIDTH+1)-1:0] entry_ras_ptr_w [0:N-1];
    wire [(ISSUE_WIDTH+2)-1:0] entry_ras_count_w [0:N-1];
    wire entry_valid_w [0:N-1];
    wire entry_pending_w [0:N-1];
    wire entry_third_w [0:N-1];
    wire [3-1:0] entry_countdown_w [0:N-1];
    reg third_valid_r;
    reg [T-1:0] third_owner_r;
    reg [T-1:0] third_tag_r;
    reg third_pending_r;
    reg [4:0] third_rs_r;
    wire third_wb_w = third_pending_r && fp_wb_valid_i && (fp_wb_tag_i == third_tag_r);
    wire third_capture_w = third_valid_r && (!third_pending_r || source0_ready_i || third_wb_w);
    wire [B-1:0] third_data_w = third_wb_w ? fp_wb_data_i :
        third_pending_r ? source0_data_i : fp_read0_data_i;
    genvar leaf;
    genvar node;
    wire q01_valid_w;
    wire [T-1:0] q01_tag_w;
    generate
        begin : g_q01
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            assign q01_valid_w = tree_valid_w[0];
            assign q01_tag_w = tree_tag_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                assign tree_valid_w[N-1+leaf] = entry_valid_w[leaf] &&
                    ib_head0_valid_i && (ISSUE_WIDTH > 0) &&
                    d0_rs1_used_w && (entry_rd_w[leaf] == d0_rs1_w) &&
                    (entry_dest_w[leaf] == (d0_rs1_domain_w ? 2'd2 : 2'd1));
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w > left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
            end
        end
    endgenerate
    wire q02_valid_w;
    wire [T-1:0] q02_tag_w;
    generate
        begin : g_q02
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            assign q02_valid_w = tree_valid_w[0];
            assign q02_tag_w = tree_tag_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                assign tree_valid_w[N-1+leaf] = entry_valid_w[leaf] &&
                    ib_head0_valid_i && (ISSUE_WIDTH > 0) &&
                    d0_rs2_used_w && (entry_rd_w[leaf] == d0_rs2_w) &&
                    (entry_dest_w[leaf] == (d0_rs2_domain_w ? 2'd2 : 2'd1));
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w > left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
            end
        end
    endgenerate
    wire q03_valid_w;
    wire [T-1:0] q03_tag_w;
    generate
        begin : g_q03
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            assign q03_valid_w = tree_valid_w[0];
            assign q03_tag_w = tree_tag_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                assign tree_valid_w[N-1+leaf] = entry_valid_w[leaf] &&
                    ib_head0_valid_i && (ISSUE_WIDTH > 0) &&
                    d0_rs3_used_w && (entry_rd_w[leaf] == d0_rs3_w) &&
                    (entry_dest_w[leaf] == (d0_rs3_domain_w ? 2'd2 : 2'd1));
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w > left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
            end
        end
    endgenerate
    wire q11_valid_w;
    wire [T-1:0] q11_tag_w;
    generate
        begin : g_q11
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            assign q11_valid_w = tree_valid_w[0];
            assign q11_tag_w = tree_tag_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                assign tree_valid_w[N-1+leaf] = entry_valid_w[leaf] &&
                    ib_head1_valid_i && (ISSUE_WIDTH > 1) &&
                    d1_rs1_used_w && (entry_rd_w[leaf] == d1_rs1_w) &&
                    (entry_dest_w[leaf] == (d1_rs1_domain_w ? 2'd2 : 2'd1));
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w > left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
            end
        end
    endgenerate
    wire q12_valid_w;
    wire [T-1:0] q12_tag_w;
    generate
        begin : g_q12
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            assign q12_valid_w = tree_valid_w[0];
            assign q12_tag_w = tree_tag_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                assign tree_valid_w[N-1+leaf] = entry_valid_w[leaf] &&
                    ib_head1_valid_i && (ISSUE_WIDTH > 1) &&
                    d1_rs2_used_w && (entry_rd_w[leaf] == d1_rs2_w) &&
                    (entry_dest_w[leaf] == (d1_rs2_domain_w ? 2'd2 : 2'd1));
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w > left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
            end
        end
    endgenerate
    wire q13_valid_w;
    wire [T-1:0] q13_tag_w;
    generate
        begin : g_q13
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            assign q13_valid_w = tree_valid_w[0];
            assign q13_tag_w = tree_tag_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                assign tree_valid_w[N-1+leaf] = entry_valid_w[leaf] &&
                    ib_head1_valid_i && (ISSUE_WIDTH > 1) &&
                    d1_rs3_used_w && (entry_rd_w[leaf] == d1_rs3_w) &&
                    (entry_dest_w[leaf] == (d1_rs3_domain_w ? 2'd2 : 2'd1));
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w > left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
            end
        end
    endgenerate
    // EX/MEM-to-ID/EX capture has a register at the consumer; no same-stage carry chain.
    wire capture0_0_w = logical_valid_w[0] && alu0_complete_valid_i &&
        (alu0_complete_tag_i == logical_tag_w[0]);
    wire capture0_1_w = logical_valid_w[0] && alu1_complete_valid_i &&
        (alu1_complete_tag_i == logical_tag_w[0]);
    wire capture0_2_w = logical_valid_w[0] && branch_complete_valid_i &&
        branch_complete_ready_i && (branch_complete_tag_i == logical_tag_w[0]);
    wire capture0_3_w = logical_valid_w[0] && mul_complete_valid_i &&
        mul_complete_ready_i && (mul_complete_tag_i == logical_tag_w[0]);
    wire capture0_4_w = logical_valid_w[0] && div_complete_valid_i &&
        div_complete_ready_i && (div_complete_tag_i == logical_tag_w[0]);
    wire capture0_5_w = logical_valid_w[0] && !lsu_complete_device_i &&
        lsu_complete_valid_i &&
        lsu_complete_ready_i && (lsu_complete_tag_i == logical_tag_w[0]);
    wire capture0_6_w = logical_valid_w[0] && csr_complete_valid_i &&
        csr_complete_ready_i && (csr_complete_tag_i == logical_tag_w[0]);
    wire capture0_7_w = logical_valid_w[0] && fp_resp_valid_i &&
        fp_resp_ready_i && (fp_resp_tag_i == logical_tag_w[0]);
    wire capture0_valid_w = capture0_0_w ||
        capture0_1_w ||
        capture0_2_w ||
        capture0_3_w ||
        capture0_4_w ||
        capture0_5_w ||
        capture0_6_w ||
        capture0_7_w;
    wire [B-1:0] capture0_data_w = ({B{capture0_0_w}} & alu0_complete_data_i) |
        ({B{capture0_1_w}} & alu1_complete_data_i) |
        ({B{capture0_2_w}} & branch_complete_data_i) |
        ({B{capture0_3_w}} & mul_complete_data_i) |
        ({B{capture0_4_w}} & div_complete_data_i) |
        ({B{capture0_5_w}} & lsu_complete_data_i) |
        ({B{capture0_6_w}} & csr_complete_data_i) |
        ({B{capture0_7_w}} & fp_resp_data_i);
    wire capture1_0_w = logical_valid_w[1] && alu0_complete_valid_i &&
        (alu0_complete_tag_i == logical_tag_w[1]);
    wire capture1_1_w = logical_valid_w[1] && alu1_complete_valid_i &&
        (alu1_complete_tag_i == logical_tag_w[1]);
    wire capture1_2_w = logical_valid_w[1] && branch_complete_valid_i &&
        branch_complete_ready_i && (branch_complete_tag_i == logical_tag_w[1]);
    wire capture1_3_w = logical_valid_w[1] && mul_complete_valid_i &&
        mul_complete_ready_i && (mul_complete_tag_i == logical_tag_w[1]);
    wire capture1_4_w = logical_valid_w[1] && div_complete_valid_i &&
        div_complete_ready_i && (div_complete_tag_i == logical_tag_w[1]);
    wire capture1_5_w = logical_valid_w[1] && !lsu_complete_device_i &&
        lsu_complete_valid_i &&
        lsu_complete_ready_i && (lsu_complete_tag_i == logical_tag_w[1]);
    wire capture1_6_w = logical_valid_w[1] && csr_complete_valid_i &&
        csr_complete_ready_i && (csr_complete_tag_i == logical_tag_w[1]);
    wire capture1_7_w = logical_valid_w[1] && fp_resp_valid_i &&
        fp_resp_ready_i && (fp_resp_tag_i == logical_tag_w[1]);
    wire capture1_valid_w = capture1_0_w ||
        capture1_1_w ||
        capture1_2_w ||
        capture1_3_w ||
        capture1_4_w ||
        capture1_5_w ||
        capture1_6_w ||
        capture1_7_w;
    wire [B-1:0] capture1_data_w = ({B{capture1_0_w}} & alu0_complete_data_i) |
        ({B{capture1_1_w}} & alu1_complete_data_i) |
        ({B{capture1_2_w}} & branch_complete_data_i) |
        ({B{capture1_3_w}} & mul_complete_data_i) |
        ({B{capture1_4_w}} & div_complete_data_i) |
        ({B{capture1_5_w}} & lsu_complete_data_i) |
        ({B{capture1_6_w}} & csr_complete_data_i) |
        ({B{capture1_7_w}} & fp_resp_data_i);
    wire capture2_0_w = logical_valid_w[2] && alu0_complete_valid_i &&
        (alu0_complete_tag_i == logical_tag_w[2]);
    wire capture2_1_w = logical_valid_w[2] && alu1_complete_valid_i &&
        (alu1_complete_tag_i == logical_tag_w[2]);
    wire capture2_2_w = logical_valid_w[2] && branch_complete_valid_i &&
        branch_complete_ready_i && (branch_complete_tag_i == logical_tag_w[2]);
    wire capture2_3_w = logical_valid_w[2] && mul_complete_valid_i &&
        mul_complete_ready_i && (mul_complete_tag_i == logical_tag_w[2]);
    wire capture2_4_w = logical_valid_w[2] && div_complete_valid_i &&
        div_complete_ready_i && (div_complete_tag_i == logical_tag_w[2]);
    wire capture2_5_w = logical_valid_w[2] && !lsu_complete_device_i &&
        lsu_complete_valid_i &&
        lsu_complete_ready_i && (lsu_complete_tag_i == logical_tag_w[2]);
    wire capture2_6_w = logical_valid_w[2] && csr_complete_valid_i &&
        csr_complete_ready_i && (csr_complete_tag_i == logical_tag_w[2]);
    wire capture2_7_w = logical_valid_w[2] && fp_resp_valid_i &&
        fp_resp_ready_i && (fp_resp_tag_i == logical_tag_w[2]);
    wire capture2_valid_w = capture2_0_w ||
        capture2_1_w ||
        capture2_2_w ||
        capture2_3_w ||
        capture2_4_w ||
        capture2_5_w ||
        capture2_6_w ||
        capture2_7_w;
    wire [B-1:0] capture2_data_w = ({B{capture2_0_w}} & alu0_complete_data_i) |
        ({B{capture2_1_w}} & alu1_complete_data_i) |
        ({B{capture2_2_w}} & branch_complete_data_i) |
        ({B{capture2_3_w}} & mul_complete_data_i) |
        ({B{capture2_4_w}} & div_complete_data_i) |
        ({B{capture2_5_w}} & lsu_complete_data_i) |
        ({B{capture2_6_w}} & csr_complete_data_i) |
        ({B{capture2_7_w}} & fp_resp_data_i);
    wire capture3_0_w = logical_valid_w[3] && alu0_complete_valid_i &&
        (alu0_complete_tag_i == logical_tag_w[3]);
    wire capture3_1_w = logical_valid_w[3] && alu1_complete_valid_i &&
        (alu1_complete_tag_i == logical_tag_w[3]);
    wire capture3_2_w = logical_valid_w[3] && branch_complete_valid_i &&
        branch_complete_ready_i && (branch_complete_tag_i == logical_tag_w[3]);
    wire capture3_3_w = logical_valid_w[3] && mul_complete_valid_i &&
        mul_complete_ready_i && (mul_complete_tag_i == logical_tag_w[3]);
    wire capture3_4_w = logical_valid_w[3] && div_complete_valid_i &&
        div_complete_ready_i && (div_complete_tag_i == logical_tag_w[3]);
    wire capture3_5_w = logical_valid_w[3] && !lsu_complete_device_i &&
        lsu_complete_valid_i &&
        lsu_complete_ready_i && (lsu_complete_tag_i == logical_tag_w[3]);
    wire capture3_6_w = logical_valid_w[3] && csr_complete_valid_i &&
        csr_complete_ready_i && (csr_complete_tag_i == logical_tag_w[3]);
    wire capture3_7_w = logical_valid_w[3] && fp_resp_valid_i &&
        fp_resp_ready_i && (fp_resp_tag_i == logical_tag_w[3]);
    wire capture3_valid_w = capture3_0_w ||
        capture3_1_w ||
        capture3_2_w ||
        capture3_3_w ||
        capture3_4_w ||
        capture3_5_w ||
        capture3_6_w ||
        capture3_7_w;
    wire [B-1:0] capture3_data_w = ({B{capture3_0_w}} & alu0_complete_data_i) |
        ({B{capture3_1_w}} & alu1_complete_data_i) |
        ({B{capture3_2_w}} & branch_complete_data_i) |
        ({B{capture3_3_w}} & mul_complete_data_i) |
        ({B{capture3_4_w}} & div_complete_data_i) |
        ({B{capture3_5_w}} & lsu_complete_data_i) |
        ({B{capture3_6_w}} & csr_complete_data_i) |
        ({B{capture3_7_w}} & fp_resp_data_i);
    wire capture4_0_w = logical_valid_w[4] && alu0_complete_valid_i &&
        (alu0_complete_tag_i == logical_tag_w[4]);
    wire capture4_1_w = logical_valid_w[4] && alu1_complete_valid_i &&
        (alu1_complete_tag_i == logical_tag_w[4]);
    wire capture4_2_w = logical_valid_w[4] && branch_complete_valid_i &&
        branch_complete_ready_i && (branch_complete_tag_i == logical_tag_w[4]);
    wire capture4_3_w = logical_valid_w[4] && mul_complete_valid_i &&
        mul_complete_ready_i && (mul_complete_tag_i == logical_tag_w[4]);
    wire capture4_4_w = logical_valid_w[4] && div_complete_valid_i &&
        div_complete_ready_i && (div_complete_tag_i == logical_tag_w[4]);
    wire capture4_5_w = logical_valid_w[4] && !lsu_complete_device_i &&
        lsu_complete_valid_i &&
        lsu_complete_ready_i && (lsu_complete_tag_i == logical_tag_w[4]);
    wire capture4_6_w = logical_valid_w[4] && csr_complete_valid_i &&
        csr_complete_ready_i && (csr_complete_tag_i == logical_tag_w[4]);
    wire capture4_7_w = logical_valid_w[4] && fp_resp_valid_i &&
        fp_resp_ready_i && (fp_resp_tag_i == logical_tag_w[4]);
    wire capture4_valid_w = capture4_0_w ||
        capture4_1_w ||
        capture4_2_w ||
        capture4_3_w ||
        capture4_4_w ||
        capture4_5_w ||
        capture4_6_w ||
        capture4_7_w;
    wire [B-1:0] capture4_data_w = ({B{capture4_0_w}} & alu0_complete_data_i) |
        ({B{capture4_1_w}} & alu1_complete_data_i) |
        ({B{capture4_2_w}} & branch_complete_data_i) |
        ({B{capture4_3_w}} & mul_complete_data_i) |
        ({B{capture4_4_w}} & div_complete_data_i) |
        ({B{capture4_5_w}} & lsu_complete_data_i) |
        ({B{capture4_6_w}} & csr_complete_data_i) |
        ({B{capture4_7_w}} & fp_resp_data_i);
    wire capture5_0_w = logical_valid_w[5] && alu0_complete_valid_i &&
        (alu0_complete_tag_i == logical_tag_w[5]);
    wire capture5_1_w = logical_valid_w[5] && alu1_complete_valid_i &&
        (alu1_complete_tag_i == logical_tag_w[5]);
    wire capture5_2_w = logical_valid_w[5] && branch_complete_valid_i &&
        branch_complete_ready_i && (branch_complete_tag_i == logical_tag_w[5]);
    wire capture5_3_w = logical_valid_w[5] && mul_complete_valid_i &&
        mul_complete_ready_i && (mul_complete_tag_i == logical_tag_w[5]);
    wire capture5_4_w = logical_valid_w[5] && div_complete_valid_i &&
        div_complete_ready_i && (div_complete_tag_i == logical_tag_w[5]);
    wire capture5_5_w = logical_valid_w[5] && !lsu_complete_device_i &&
        lsu_complete_valid_i &&
        lsu_complete_ready_i && (lsu_complete_tag_i == logical_tag_w[5]);
    wire capture5_6_w = logical_valid_w[5] && csr_complete_valid_i &&
        csr_complete_ready_i && (csr_complete_tag_i == logical_tag_w[5]);
    wire capture5_7_w = logical_valid_w[5] && fp_resp_valid_i &&
        fp_resp_ready_i && (fp_resp_tag_i == logical_tag_w[5]);
    wire capture5_valid_w = capture5_0_w ||
        capture5_1_w ||
        capture5_2_w ||
        capture5_3_w ||
        capture5_4_w ||
        capture5_5_w ||
        capture5_6_w ||
        capture5_7_w;
    wire [B-1:0] capture5_data_w = ({B{capture5_0_w}} & alu0_complete_data_i) |
        ({B{capture5_1_w}} & alu1_complete_data_i) |
        ({B{capture5_2_w}} & branch_complete_data_i) |
        ({B{capture5_3_w}} & mul_complete_data_i) |
        ({B{capture5_4_w}} & div_complete_data_i) |
        ({B{capture5_5_w}} & lsu_complete_data_i) |
        ({B{capture5_6_w}} & csr_complete_data_i) |
        ({B{capture5_7_w}} & fp_resp_data_i);
    wire p0_w = (d0_class_w == 3'd6) && ib_head0_valid_i && !d0_exception_w;
    wire p1_w = (ISSUE_WIDTH == 2) && (d1_class_w == 3'd6) &&
        ib_head1_valid_i && !d1_exception_w;
    wire fp_slot_w = !p0_w && p1_w;
    wire fp_present_w = p0_w || p1_w;
    reg [2:0] physical_w [0:5];
    reg [2:0] query_w [0:4];
    wire logical_valid_w [0:5];
    wire [T-1:0] logical_tag_w [0:5];
    wire logical_domain_w [0:5];
    wire logical_used_w [0:5];
    wire [B-1:0] rf_value_w [0:5];
    wire source_ready_w [0:4];
    wire [B-1:0] source_data_w [0:4];
    wire [B-1:0] value_w [0:5];
    wire value_ready_w [0:5];
    wire source_valid_w [0:4];
    wire [T-1:0] source_tag_w [0:4];
    wire [B-1:0] fp_rf_value_w [0:2];
    assign fp_rf_value_w[0] = fp_read0_data_i;
    assign fp_rf_value_w[1] = fp_read1_data_i;
    assign fp_rf_value_w[2] = fp_read2_data_i;
    // query index 6 denotes the unneeded x0 source.
    wire [T-1:0] query_tag_w [0:6];
    wire query_valid_w [0:6];
    wire query_domain_w [0:6];
    assign logical_valid_w[0] = q01_valid_w;
    assign logical_tag_w[0] = q01_tag_w;
    assign logical_domain_w[0] = d0_rs1_domain_w;
    assign logical_used_w[0] = d0_rs1_used_w;
    assign query_tag_w[0] = logical_tag_w[0];
    assign query_valid_w[0] = logical_valid_w[0];
    assign query_domain_w[0] = logical_domain_w[0];
    assign rf_value_w[0] = d0_rs1_domain_w ?
        fp_rf_value_w[(d0_store_w ? 2'd0 : 2'd0)] : {{(B-32){1'b0}}, id_data0_i};
    assign value_ready_w[0] = !logical_used_w[0] || !logical_valid_w[0] || capture0_valid_w ||
        source_ready_w[physical_w[0]];
    assign value_w[0] = capture0_valid_w ? capture0_data_w : logical_valid_w[0] ?
        source_data_w[physical_w[0]] : rf_value_w[0];
    assign logical_valid_w[1] = q02_valid_w;
    assign logical_tag_w[1] = q02_tag_w;
    assign logical_domain_w[1] = d0_rs2_domain_w;
    assign logical_used_w[1] = d0_rs2_used_w;
    assign query_tag_w[1] = logical_tag_w[1];
    assign query_valid_w[1] = logical_valid_w[1];
    assign query_domain_w[1] = logical_domain_w[1];
    assign rf_value_w[1] = d0_rs2_domain_w ?
        fp_rf_value_w[(d0_store_w ? 2'd0 : 2'd1)] : {{(B-32){1'b0}}, id_data1_i};
    assign value_ready_w[1] = !logical_used_w[1] || !logical_valid_w[1] || capture1_valid_w ||
        source_ready_w[physical_w[1]];
    assign value_w[1] = capture1_valid_w ? capture1_data_w : logical_valid_w[1] ?
        source_data_w[physical_w[1]] : rf_value_w[1];
    assign logical_valid_w[2] = q03_valid_w;
    assign logical_tag_w[2] = q03_tag_w;
    assign logical_domain_w[2] = d0_rs3_domain_w;
    assign logical_used_w[2] = d0_rs3_used_w;
    assign query_tag_w[2] = logical_tag_w[2];
    assign query_valid_w[2] = logical_valid_w[2];
    assign query_domain_w[2] = logical_domain_w[2];
    assign rf_value_w[2] = d0_rs3_domain_w ?
        fp_rf_value_w[(d0_store_w ? 2'd0 : 2'd2)] : {{(B-32){1'b0}}, 32'd0};
    assign value_ready_w[2] = !logical_used_w[2] || !logical_valid_w[2] || capture2_valid_w ||
        source_ready_w[physical_w[2]];
    assign value_w[2] = capture2_valid_w ? capture2_data_w : logical_valid_w[2] ?
        source_data_w[physical_w[2]] : rf_value_w[2];
    assign logical_valid_w[3] = q11_valid_w;
    assign logical_tag_w[3] = q11_tag_w;
    assign logical_domain_w[3] = d1_rs1_domain_w;
    assign logical_used_w[3] = d1_rs1_used_w;
    assign query_tag_w[3] = logical_tag_w[3];
    assign query_valid_w[3] = logical_valid_w[3];
    assign query_domain_w[3] = logical_domain_w[3];
    assign rf_value_w[3] = d1_rs1_domain_w ?
        fp_rf_value_w[(d1_store_w ? 2'd0 : 2'd0)] : {{(B-32){1'b0}}, id_data2_i};
    assign value_ready_w[3] = !logical_used_w[3] || !logical_valid_w[3] || capture3_valid_w ||
        source_ready_w[physical_w[3]];
    assign value_w[3] = capture3_valid_w ? capture3_data_w : logical_valid_w[3] ?
        source_data_w[physical_w[3]] : rf_value_w[3];
    assign logical_valid_w[4] = q12_valid_w;
    assign logical_tag_w[4] = q12_tag_w;
    assign logical_domain_w[4] = d1_rs2_domain_w;
    assign logical_used_w[4] = d1_rs2_used_w;
    assign query_tag_w[4] = logical_tag_w[4];
    assign query_valid_w[4] = logical_valid_w[4];
    assign query_domain_w[4] = logical_domain_w[4];
    assign rf_value_w[4] = d1_rs2_domain_w ?
        fp_rf_value_w[(d1_store_w ? 2'd0 : 2'd1)] : {{(B-32){1'b0}}, id_data3_i};
    assign value_ready_w[4] = !logical_used_w[4] || !logical_valid_w[4] || capture4_valid_w ||
        source_ready_w[physical_w[4]];
    assign value_w[4] = capture4_valid_w ? capture4_data_w : logical_valid_w[4] ?
        source_data_w[physical_w[4]] : rf_value_w[4];
    assign logical_valid_w[5] = q13_valid_w;
    assign logical_tag_w[5] = q13_tag_w;
    assign logical_domain_w[5] = d1_rs3_domain_w;
    assign logical_used_w[5] = d1_rs3_used_w;
    assign query_tag_w[5] = logical_tag_w[5];
    assign query_valid_w[5] = logical_valid_w[5];
    assign query_domain_w[5] = logical_domain_w[5];
    assign rf_value_w[5] = d1_rs3_domain_w ?
        fp_rf_value_w[(d1_store_w ? 2'd0 : 2'd2)] : {{(B-32){1'b0}}, 32'd0};
    assign value_ready_w[5] = !logical_used_w[5] || !logical_valid_w[5] || capture5_valid_w ||
        source_ready_w[physical_w[5]];
    assign value_w[5] = capture5_valid_w ? capture5_data_w : logical_valid_w[5] ?
        source_data_w[physical_w[5]] : rf_value_w[5];
    assign query_tag_w[6] = {T{1'b0}};
    assign query_valid_w[6] = 1'b0;
    assign query_domain_w[6] = 1'b0;
    always @(*) begin
        physical_w[0]=3'd0; physical_w[1]=3'd1; physical_w[2]=3'd0;
        physical_w[3]=3'd2; physical_w[4]=3'd3; physical_w[5]=3'd0;
        query_w[0]=3'd0; query_w[1]=3'd1; query_w[2]=3'd3;
        query_w[3]=3'd4; query_w[4]=3'd6;
        if (fp_present_w) begin
            if (!fp_slot_w) begin
                physical_w[0]=3'd0; physical_w[1]=3'd1; physical_w[2]=3'd2;
                physical_w[3]=R; physical_w[4]=R+1'b1;
                query_w[0]=3'd0; query_w[1]=3'd1; query_w[2]=3'd2;
                if (d0_store_w) begin
                    physical_w[0]=3'd1;physical_w[1]=3'd0;
                    query_w[0]=3'd1;query_w[1]=3'd0;
                end
            end else begin
                physical_w[3]=3'd0;physical_w[4]=3'd1;physical_w[5]=3'd2;
                physical_w[0]=R;physical_w[1]=R+1'b1;
                query_w[0]=3'd3;query_w[1]=3'd4;query_w[2]=3'd5;
                if (d1_store_w) begin
                    physical_w[3]=3'd1;physical_w[4]=3'd0;
                    query_w[0]=3'd4;query_w[1]=3'd3;
                end
            end
            if (R == 2) begin
                query_w[2]=fp_slot_w ? 3'd0 : 3'd3;
                query_w[3]=fp_slot_w ? 3'd1 : 3'd4;
            end else begin
                query_w[3]=fp_slot_w ? 3'd0 : 3'd3;
                query_w[4]=fp_slot_w ? 3'd1 : 3'd4;
            end
        end
        if (third_valid_r) begin
            physical_w[0]=R;physical_w[1]=R+1'b1;
            query_w[0]=3'd6;query_w[R]=3'd0;query_w[R+1]=3'd1;
        end
    end
    assign source_ready_w[0] = source0_ready_i;
    assign source_data_w[0] = source0_data_i;
    assign source_valid_w[0] = (0 < S) &&
        (third_valid_r ? third_pending_r : query_valid_w[query_w[0]]);
    assign source_tag_w[0] = (third_valid_r ? third_tag_r : query_tag_w[query_w[0]]);
    assign source0_valid_o = source_valid_w[0];
    assign source0_tag_o = (0 < S) ? source_tag_w[0] : {T{1'b0}};
    assign source0_domain_o = (0 < S) && (third_valid_r || query_domain_w[query_w[0]]);
    assign source_ready_w[1] = source1_ready_i;
    assign source_data_w[1] = source1_data_i;
    assign source_valid_w[1] = (1 < S) &&
        query_valid_w[query_w[1]];
    assign source_tag_w[1] = query_tag_w[query_w[1]];
    assign source1_valid_o = source_valid_w[1];
    assign source1_tag_o = (1 < S) ? source_tag_w[1] : {T{1'b0}};
    assign source1_domain_o = (1 < S) && query_domain_w[query_w[1]];
    assign source_ready_w[2] = source2_ready_i;
    assign source_data_w[2] = source2_data_i;
    assign source_valid_w[2] = (2 < S) &&
        query_valid_w[query_w[2]];
    assign source_tag_w[2] = query_tag_w[query_w[2]];
    assign source2_valid_o = source_valid_w[2];
    assign source2_tag_o = (2 < S) ? source_tag_w[2] : {T{1'b0}};
    assign source2_domain_o = (2 < S) && query_domain_w[query_w[2]];
    assign source_ready_w[3] = source3_ready_i;
    assign source_data_w[3] = source3_data_i;
    assign source_valid_w[3] = (3 < S) &&
        query_valid_w[query_w[3]];
    assign source_tag_w[3] = query_tag_w[query_w[3]];
    assign source3_valid_o = source_valid_w[3];
    assign source3_tag_o = (3 < S) ? source_tag_w[3] : {T{1'b0}};
    assign source3_domain_o = (3 < S) && query_domain_w[query_w[3]];
    assign source_ready_w[4] = source4_ready_i;
    assign source_data_w[4] = source4_data_i;
    assign source_valid_w[4] = (4 < S) &&
        query_valid_w[query_w[4]];
    assign source_tag_w[4] = query_tag_w[query_w[4]];
    assign source4_valid_o = source_valid_w[4];
    assign source4_tag_o = (4 < S) ? source_tag_w[4] : {T{1'b0}};
    assign source4_domain_o = (4 < S) && query_domain_w[query_w[4]];
    assign fp_read0_addr_o = (FPU_FORMAT != "NONE") && (0 < R) ?
        (third_valid_r ? third_rs_r :
        ((fp_slot_w ? d1_store_w : d0_store_w) ?
        (fp_slot_w ? d1_rs2_w : d0_rs2_w) : (fp_slot_w ? d1_rs1_w : d0_rs1_w))) : 5'd0;
    assign fp_read1_addr_o = (FPU_FORMAT != "NONE") && (1 < R) ?
        ((fp_slot_w ? d1_rs2_w : d0_rs2_w)) : 5'd0;
    assign fp_read2_addr_o = (FPU_FORMAT != "NONE") && (2 < R) ?
        ((fp_slot_w ? d1_rs3_w : d0_rs3_w)) : 5'd0;
    wire channel_valid_w [0:7];
    wire [T-1:0] channel_tag_w [0:7];
    wire [T:0] channel_count_w [0:7];
    wire channel_ready_w [0:7];
    assign channel_ready_w[0] = execute0_ready_i;
    generate
        begin : g_channel0
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[0] = tree_valid_w[0];
            assign channel_tag_w[0] = tree_tag_w[0];
            assign channel_count_w[0] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd0);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[1] = execute1_ready_i;
    generate
        begin : g_channel1
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[1] = tree_valid_w[0];
            assign channel_tag_w[1] = tree_tag_w[0];
            assign channel_count_w[1] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = (ISSUE_WIDTH == 2) && entry_pending_w[leaf] &&
                    (entry_channel_w[leaf] == 3'd1);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[2] = mul_req_ready_i;
    generate
        begin : g_channel2
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[2] = tree_valid_w[0];
            assign channel_tag_w[2] = tree_tag_w[0];
            assign channel_count_w[2] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd2);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[3] = div_req_ready_i;
    generate
        begin : g_channel3
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[3] = tree_valid_w[0];
            assign channel_tag_w[3] = tree_tag_w[0];
            assign channel_count_w[3] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd3);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[4] = lsu_req_ready_i;
    generate
        begin : g_channel4
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[4] = tree_valid_w[0];
            assign channel_tag_w[4] = tree_tag_w[0];
            assign channel_count_w[4] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd4);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[5] = csr_req_ready_i;
    generate
        begin : g_channel5
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[5] = tree_valid_w[0];
            assign channel_tag_w[5] = tree_tag_w[0];
            assign channel_count_w[5] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd5);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[6] = fp_req_ready_i;
    generate
        begin : g_channel6
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[6] = tree_valid_w[0];
            assign channel_tag_w[6] = tree_tag_w[0];
            assign channel_count_w[6] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd6);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    assign channel_ready_w[7] = decode_complete_ready_i;
    generate
        begin : g_channel7
            wire tree_valid_w [0:2*N-2] /* verilator split_var */;
            wire [T-1:0] tree_tag_w [0:2*N-2] /* verilator split_var */;
            wire [T:0] tree_count_w [0:2*N-2] /* verilator split_var */;
            assign channel_valid_w[7] = tree_valid_w[0];
            assign channel_tag_w[7] = tree_tag_w[0];
            assign channel_count_w[7] = tree_count_w[0];
            for (leaf=0; leaf<N; leaf=leaf+1) begin : g_leaf
                localparam [T-1:0] TAG = leaf;
                wire pending_w = entry_pending_w[leaf] && (entry_channel_w[leaf] == 3'd7);
                assign tree_valid_w[N-1+leaf] = pending_w && !entry_third_w[leaf] &&
                    entry_dispatch_ready_w[leaf];
                assign tree_count_w[N-1+leaf] = {{T{1'b0}}, pending_w};
                assign tree_tag_w[N-1+leaf] = TAG;
            end
            for (node=0; node<N-1; node=node+1) begin : g_node
                wire [T-1:0] left_age_w = tree_tag_w[2*node+1]-age_head_i;
                wire [T-1:0] right_age_w = tree_tag_w[2*node+2]-age_head_i;
                wire choose_w = tree_valid_w[2*node+2] &&
                    (!tree_valid_w[2*node+1] || (right_age_w < left_age_w));
                assign tree_valid_w[node] = tree_valid_w[2*node+1] || tree_valid_w[2*node+2];
                assign tree_tag_w[node] = choose_w ? tree_tag_w[2*node+2] : tree_tag_w[2*node+1];
                assign tree_count_w[node] = tree_count_w[2*node+1]+tree_count_w[2*node+2];
            end
        end
    endgenerate
    wire d0_pipe1_w = (d0_class_w <= 3'd2) || (d0_class_w == 3'd4);
    wire d1_pipe1_w = (d1_class_w <= 3'd2) || (d1_class_w == 3'd4);
    wire swap_w = !d1_pipe1_w && d0_pipe1_w;
    wire raw1_w = (d0_dest_w != 2'd0) && d1_rs1_used_w &&
        (d0_rd_w == d1_rs1_w) && (d0_dest_w == (d1_rs1_domain_w ? 2'd2 : 2'd1));
    wire raw2_w = (d0_dest_w != 2'd0) && d1_rs2_used_w &&
        (d0_rd_w == d1_rs2_w) && (d0_dest_w == (d1_rs2_domain_w ? 2'd2 : 2'd1));
    wire raw3_w = (d0_dest_w != 2'd0) && d1_rs3_used_w &&
        (d0_rd_w == d1_rs3_w) && (d0_dest_w == (d1_rs3_domain_w ? 2'd2 : 2'd1));
    wire group_raw_w = raw1_w || raw2_w || raw3_w;
    wire types_pair_w = (d0_pipe1_w || d1_pipe1_w) &&
        (d0_class_w != 3'd7) && (d1_class_w != 3'd7) &&
        !((d0_class_w == d1_class_w) && (d0_class_w != 3'd0)) &&
        !((d0_class_w <= 3'd2) && (d0_class_w != 3'd0) &&
            (d1_class_w <= 3'd2) && (d1_class_w != 3'd0)) &&
        ((d0_class_w != 3'd6) || (d1_class_w == 3'd0)) &&
        ((d1_class_w != 3'd6) || (d0_class_w == 3'd0));
    wire d0_wait1_w = d0_rs1_used_w && !value_ready_w[0];
    wire d0_defer1_w = d0_wait1_w &&
        (entry_countdown_w[q01_tag_w] == 3'd1) &&
        ((entry_class_w[q01_tag_w] == 3'd3) ||
        (entry_class_w[q01_tag_w] == 3'd0));
    wire d0_wait2_w = d0_rs2_used_w && !value_ready_w[1];
    wire d0_defer2_w = d0_wait2_w &&
        (entry_countdown_w[q02_tag_w] == 3'd1) &&
        ((entry_class_w[q02_tag_w] == 3'd3) ||
        (entry_class_w[q02_tag_w] == 3'd0));
    wire d0_late_w = (ISSUE_WIDTH == 2) && d0_late_supported_w &&
        (d0_wait1_w || d0_wait2_w) &&
        (!d0_wait1_w || d0_defer1_w) && (!d0_wait2_w || d0_defer2_w);
    // Predict only the registered early candidate, independently of the hit result.
    wire d0_short1_w = ISSUE_WIDTH == 1 && d0_wait1_w && !d0_rs1_domain_w &&
        entry_early_w[q01_tag_w] && entry_pending_w[q01_tag_w] &&
        entry_channel_w[q01_tag_w] == 3'd4 && channel_count_w[4] == 1 && lsu_req_ready_i;
    wire d0_short2_w = ISSUE_WIDTH == 1 && d0_wait2_w && !d0_rs2_domain_w &&
        entry_early_w[q02_tag_w] && entry_pending_w[q02_tag_w] &&
        entry_channel_w[q02_tag_w] == 3'd4 && channel_count_w[4] == 1 && lsu_req_ready_i;
    wire d0_sources_w = (((!d0_wait1_w || d0_short1_w) &&
        (!d0_wait2_w || d0_short2_w)) || d0_late_w) &&
        (!d0_rs3_used_w || (FPU_FORMAT == "FD") || value_ready_w[2]);
    wire d0_ordered_w = (d0_class_w != 3'd7) || (allocate_credit_i == N);
    wire [2:0] d0_base_channel_w = d0_exception_w ? 3'd7 :
        d0_class_w == 3'd4 ? 3'd2 : d0_class_w == 3'd5 ? 3'd3 :
        (d0_class_w == 3'd3 || d0_load_w || d0_store_w) ? 3'd4 :
        d0_class_w == 3'd7 ? 3'd5 : d0_class_w == 3'd6 ? 3'd6 : 3'd0;
    wire d1_wait1_w = d1_rs1_used_w && !value_ready_w[3];
    wire d1_defer1_w = d1_wait1_w &&
        (entry_countdown_w[q11_tag_w] == 3'd1) &&
        ((entry_class_w[q11_tag_w] == 3'd3) ||
        (entry_class_w[q11_tag_w] == 3'd0));
    wire d1_wait2_w = d1_rs2_used_w && !value_ready_w[4];
    wire d1_defer2_w = d1_wait2_w &&
        (entry_countdown_w[q12_tag_w] == 3'd1) &&
        ((entry_class_w[q12_tag_w] == 3'd3) ||
        (entry_class_w[q12_tag_w] == 3'd0));
    wire d1_late_w = (ISSUE_WIDTH == 2) && d1_late_supported_w &&
        (d1_wait1_w || d1_wait2_w) &&
        (!d1_wait1_w || d1_defer1_w) && (!d1_wait2_w || d1_defer2_w);
    wire d1_sources_w = ((!d1_wait1_w && !d1_wait2_w) || d1_late_w) &&
        (!d1_rs3_used_w || (FPU_FORMAT == "FD") || value_ready_w[5]);
    wire d1_ordered_w = (d1_class_w != 3'd7) || (allocate_credit_i == N);
    wire [2:0] d1_base_channel_w = d1_exception_w ? 3'd7 :
        d1_class_w == 3'd4 ? 3'd2 : d1_class_w == 3'd5 ? 3'd3 :
        (d1_class_w == 3'd3 || d1_load_w || d1_store_w) ? 3'd4 :
        d1_class_w == 3'd7 ? 3'd5 : d1_class_w == 3'd6 ? 3'd6 : 3'd0;
    wire early0_w;
    wire early1_w;
    wire [31:0] early0_addr_w;
    wire [31:0] early1_addr_w;
    wire group_late_w = (ISSUE_WIDTH == 2) && group_raw_w && !raw3_w &&
        d1_late_supported_w && (d0_dest_w == 2'd1) && !d0_late_w &&
        ((d0_class_w == 3'd0) || ((d0_class_w == 3'd3) && early0_w));
    wire raw_pair_w = !group_raw_w ||
        (group_late_w && (!d1_wait1_w || raw1_w || d1_defer1_w) &&
        (!d1_wait2_w || raw2_w || d1_defer2_w));
    wire pair_candidate_w = (ISSUE_WIDTH == 2) && ib_head1_valid_i &&
        (allocate_credit_i >= 2) && types_pair_w && raw_pair_w &&
        (d1_sources_w || group_late_w) && d1_ordered_w && !third_valid_r &&
        ((d1_class_w != 3'd6) || !(|serial_pending_w));
    wire [2:0] pair_channel0_w = (d0_base_channel_w == 3'd0 && swap_w) ? 3'd1 :
        d0_base_channel_w;
    wire [2:0] pair_channel1_w = (d1_base_channel_w == 3'd0 && !swap_w) ? 3'd1 :
        d1_base_channel_w;
    wire pair_capacity_w = (channel_count_w[pair_channel0_w] < 2) &&
        (channel_count_w[pair_channel1_w] < 2) &&
        ((pair_channel0_w != pair_channel1_w) || (channel_count_w[pair_channel0_w] == 0));
    wire use_pair_w = pair_candidate_w && pair_capacity_w;
    wire [2:0] channel0_w = use_pair_w ? pair_channel0_w : d0_base_channel_w;
    wire [2:0] channel1_w = pair_channel1_w;
    wire head_ready_w = ((d0_class_w != 3'd6) || !(|serial_pending_w)) &&
        ib_head0_valid_i && (allocate_credit_i != 0) &&
        d0_sources_w && d0_ordered_w && (channel_count_w[channel0_w] < 2) &&
        (!p0_w || !third_valid_r);
    assign allocate_valid_o = head_ready_w && !cancel_valid_i;
    assign allocate_count_o = head_ready_w ? (use_pair_w ? 2'd2 : 2'd1) : 2'd0;
    assign ib_remove_count_o = fire_w ? allocate_count_o : 2'd0;
    wire allocate0_w = fire_w;
    wire allocate1_w = fire_w && use_pair_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            tail_r <= {T{1'b0}};
        else if (cancel_valid_i)
            tail_r <= cancel_tag_i;
        else if (fire_w)
            tail_r <= tail_r + {{(T-2){1'b0}}, allocate_count_o};
    end
    wire unused_early0_valid_w;
    wire [31:0] unused_early0_addr_w;
    wire [T-1:0] unused_early0_tag_w;
    edrv32_cpu2_id_agu #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_agu0 (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .id_valid_i(allocate0_w),
        .id_load_i(d0_load_w),
        .id_store_i(d0_store_w),
        .id_rs1_i(d0_rs1_w),
        .id_candidates_i(ib_head0_candidates_i),
        .id_imm_i(d0_imm_w),
        .id_tag_i(tag0_w),
        .rs1_pending_i((q01_valid_w)),
        .wb0_valid_i(wb0_valid_i),
        .wb0_rd_i(wb0_rd_i),
        .wb0_data_i(wb0_data_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_rd_i(wb1_rd_i),
        .wb1_data_i(wb1_data_i),
        .id_eligible_o(early0_w),
        .id_addr_o(early0_addr_w),
        .early_req_valid_o(unused_early0_valid_w),
        .early_req_addr_o(unused_early0_addr_w),
        .early_req_tag_o(unused_early0_tag_w)
    );
    wire unused_early1_valid_w;
    wire [31:0] unused_early1_addr_w;
    wire [T-1:0] unused_early1_tag_w;
    generate
        if (ISSUE_WIDTH == 2) begin : g_second_agu
            edrv32_cpu2_id_agu #(
                .ISSUE_WIDTH(ISSUE_WIDTH),
                .FPU_FORMAT(FPU_FORMAT)
            ) u_agu1 (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .id_valid_i(allocate1_w),
                .id_load_i(d1_load_w),
                .id_store_i(d1_store_w),
                .id_rs1_i(d1_rs1_w),
                .id_candidates_i(ib_head1_candidates_i),
                .id_imm_i(d1_imm_w),
                .id_tag_i(tag1_w),
                .rs1_pending_i((q11_valid_w) || raw1_w),
                .wb0_valid_i(wb0_valid_i),
                .wb0_rd_i(wb0_rd_i),
                .wb0_data_i(wb0_data_i),
                .wb1_valid_i(wb1_valid_i),
                .wb1_rd_i(wb1_rd_i),
                .wb1_data_i(wb1_data_i),
                .id_eligible_o(early1_w),
                .id_addr_o(early1_addr_w),
                .early_req_valid_o(unused_early1_valid_w),
                .early_req_addr_o(unused_early1_addr_w),
                .early_req_tag_o(unused_early1_tag_w)
            );
        end else begin : g_no_second_agu
            assign early1_w = 1'b0;
            assign early1_addr_w = 32'd0;
            assign unused_early1_valid_w = 1'b0;
            assign unused_early1_addr_w = 32'd0;
            assign unused_early1_tag_w = {T{1'b0}};
        end
    endgenerate
    assign early_req_valid_o = (allocate0_w && early0_w) || (allocate1_w && early1_w);
    assign early_req_addr_o = (allocate0_w && early0_w) ? early0_addr_w : early1_addr_w;
    assign early_req_tag_o = (allocate0_w && early0_w) ? tag0_w : tag1_w;
    assign allocate0_tag_o = tag0_w;
    assign allocate0_pc_o = ib_head0_pc_i;
    assign allocate0_instr_o = ib_head0_instr_i;
    assign allocate0_rd_o = d0_rd_w;
    assign allocate0_dest_o = d0_dest_w;
    assign allocate0_csr_src_o = ib_head0_instr_i[14] ? {27'd0, d0_rs1_w} : value_w[0][31:0];
    assign allocate0_store_o = d0_store_w;
    assign allocate0_divide_o = d0_class_w == 3'd5;
    assign allocate0_double_beat_o = d0_double_beat_w;
    assign predict_read0_valid_o = (ISSUE_WIDTH == 2) && allocate0_w &&
        ib_head0_predict_token_i && (ib_head0_instr_i[6:0] == 7'h63);
    assign predict_read0_tag_o = (ISSUE_WIDTH == 2) ? tag0_w : {T{1'b0}};
    assign predict_read0_index0_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_index0_i : 9'd0;
    assign predict_read0_index1_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_index1_i : 9'd0;
    assign predict_read0_index2_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_index2_i : 9'd0;
    assign predict_read0_index3_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_index3_i : 9'd0;
    assign predict_read0_tag0_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_tag0_i : 10'd0;
    assign predict_read0_tag1_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_tag1_i : 10'd0;
    assign predict_read0_tag2_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_tag2_i : 10'd0;
    assign predict_read0_tag3_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_tag3_i : 10'd0;
    assign predict_read0_base_index_o = (ISSUE_WIDTH == 2) ?
        ib_head0_predict_base_index_i : 12'd0;
    assign allocate1_tag_o = (ISSUE_WIDTH == 2) ? (tag1_w) : 0;
    assign allocate1_pc_o = (ISSUE_WIDTH == 2) ? (ib_head1_pc_i) : 0;
    assign allocate1_instr_o = (ISSUE_WIDTH == 2) ? (ib_head1_instr_i) : 0;
    assign allocate1_rd_o = (ISSUE_WIDTH == 2) ? (d1_rd_w) : 0;
    assign allocate1_dest_o = (ISSUE_WIDTH == 2) ? (d1_dest_w) : 0;
    assign allocate1_csr_src_o =
        (ISSUE_WIDTH == 2) ? (ib_head1_instr_i[14] ? {27'd0, d1_rs1_w} : value_w[3][31:0]) : 0;
    assign allocate1_store_o = (ISSUE_WIDTH == 2) ? (d1_store_w) : 0;
    assign allocate1_divide_o = (ISSUE_WIDTH == 2) ? (d1_class_w == 3'd5) : 0;
    assign allocate1_double_beat_o = (ISSUE_WIDTH == 2) ? (d1_double_beat_w) : 0;
    assign predict_read1_valid_o = (ISSUE_WIDTH == 2) && allocate1_w &&
        ib_head1_predict_token_i && (ib_head1_instr_i[6:0] == 7'h63);
    assign predict_read1_tag_o = (ISSUE_WIDTH == 2) ? tag1_w : {T{1'b0}};
    assign predict_read1_index0_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_index0_i : 9'd0;
    assign predict_read1_index1_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_index1_i : 9'd0;
    assign predict_read1_index2_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_index2_i : 9'd0;
    assign predict_read1_index3_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_index3_i : 9'd0;
    assign predict_read1_tag0_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_tag0_i : 10'd0;
    assign predict_read1_tag1_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_tag1_i : 10'd0;
    assign predict_read1_tag2_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_tag2_i : 10'd0;
    assign predict_read1_tag3_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_tag3_i : 10'd0;
    assign predict_read1_base_index_o = (ISSUE_WIDTH == 2) ?
        ib_head1_predict_base_index_i : 12'd0;
    wire third_start0_w = allocate0_w && d0_rs3_used_w && (FPU_FORMAT == "FD");
    wire third_start1_w = allocate1_w && d1_rs3_used_w && (FPU_FORMAT == "FD");
    wire third_start_w = third_start0_w || third_start1_w;
    wire [T-1:0] start_tag_w = third_start0_w ? q03_tag_w : q13_tag_w;
    wire start_pending_w = third_start0_w ? q03_valid_w : q13_valid_w;
    wire [4:0] start_rs_w = third_start0_w ? d0_rs3_w : d1_rs3_w;
    wire start_wb_w = start_pending_w && fp_wb_valid_i && (fp_wb_tag_i == start_tag_w);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            third_valid_r <= 1'b0;
        else if (cancel_valid_i && ((third_owner_r-age_head_i) >= cancel_age_w))
            third_valid_r <= 1'b0;
        else if (third_start_w)
            third_valid_r <= !start_wb_w;
        else if (third_capture_w)
            third_valid_r <= 1'b0;
    end
    always @(posedge clk_i) begin
        if (third_start_w) begin
            third_owner_r <= third_start0_w ? tag0_w : tag1_w;
            third_tag_r <= start_tag_w;
            third_pending_r <= start_pending_w;
            third_rs_r <= start_rs_w;
        end
    end
    genvar entry;
    genvar operand;
    generate
        for (entry=0; entry<N; entry=entry+1) begin : g_entry
            localparam [T-1:0] ENTRY = entry;
            reg [32-1:0] pc_r;
            assign entry_pc_w[entry] = pc_r;
            reg [32-1:0] instr_r;
            assign entry_instr_w[entry] = instr_r;
            reg [5-1:0] rd_r;
            assign entry_rd_w[entry] = rd_r;
            reg [2-1:0] dest_r;
            assign entry_dest_w[entry] = dest_r;
            reg [3-1:0] class_r;
            assign entry_class_w[entry] = class_r;
            reg [3-1:0] channel_r;
            assign entry_channel_w[entry] = channel_r;
            reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] src1_r;
            wire short1_w;
            wire short2_w;
            assign entry_src1_w[entry] = short1_w ? {{(B-32){1'b0}}, early_resp_data_i} : src1_r;
            reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] src2_r;
            assign entry_src2_w[entry] = short2_w ? {{(B-32){1'b0}}, early_resp_data_i} : src2_r;
            reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] src3_r;
            assign entry_src3_w[entry] = src3_r;
            reg [32-1:0] imm_r;
            assign entry_imm_w[entry] = imm_r;
            reg late_r;
            assign entry_late_w[entry] = late_r;
            reg [T-1:0] source1_tag_r;
            assign entry_source1_tag_w[entry] = source1_tag_r;
            reg [T-1:0] source2_tag_r;
            assign entry_source2_tag_w[entry] = source2_tag_r;
            reg source1_wait_r;
            assign entry_source1_wait_w[entry] = source1_wait_r;
            reg source2_wait_r;
            assign entry_source2_wait_w[entry] = source2_wait_r;
            assign short1_w = ISSUE_WIDTH == 1 && source1_wait_r &&
                early_resp_valid_i && early_resp_hit_i && early_resp_tag_i == source1_tag_r;
            assign short2_w = ISSUE_WIDTH == 1 && source2_wait_r &&
                early_resp_valid_i && early_resp_hit_i && early_resp_tag_i == source2_tag_r;
            assign entry_dispatch_ready_w[entry] = ISSUE_WIDTH == 2 ||
                ((!source1_wait_r || short1_w) && (!source2_wait_r || short2_w));
            wire [1:0] pending_source_valid_w;
            wire [B-1:0] pending_source_data_w [0:1];
            // Local EX backpressure may outlive a producer's result and retirement.
            // Retain the value in the existing source FFs, independently of dispatch.
            for (operand = 0; operand < 2; operand = operand + 1) begin : g_pending_source
                wire [T-1:0] pending_tag_w = operand == 0 ? source1_tag_r : source2_tag_r;
                wire early_w = early_resp_valid_i && early_resp_hit_i &&
                    early_resp_tag_i == pending_tag_w;
                wire ordinary_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                    !lsu_complete_device_i && lsu_complete_tag_i == pending_tag_w;
                wire alu0_w = ISSUE_WIDTH == 2 && alu0_complete_valid_i &&
                    alu0_complete_tag_i == pending_tag_w;
                wire alu1_w = ISSUE_WIDTH == 2 && alu1_complete_valid_i &&
                    alu1_complete_tag_i == pending_tag_w;
                wire wb0_w = wb0_valid_i && wb0_tag_i == pending_tag_w;
                wire wb1_w = ISSUE_WIDTH == 2 && wb1_valid_i && wb1_tag_i == pending_tag_w;
                assign pending_source_valid_w[operand] = early_w || ordinary_w ||
                    alu0_w || alu1_w || wb0_w || wb1_w;
                assign pending_source_data_w[operand] =
                    ({B{early_w}} & {{(B-32){1'b0}}, early_resp_data_i}) |
                    ({B{ordinary_w}} & lsu_complete_data_i) |
                    ({B{alu0_w}} & alu0_complete_data_i) |
                    ({B{alu1_w}} & alu1_complete_data_i) |
                    ({B{wb0_w}} & {{(B-32){1'b0}}, wb0_data_i}) |
                    ({B{wb1_w}} & {{(B-32){1'b0}}, wb1_data_i});
            end
            reg early_r;
            assign entry_early_w[entry] = early_r;
            reg [3-1:0] rm_r;
            assign entry_rm_w[entry] = rm_r;
            reg [4-1:0] cause_r;
            assign entry_cause_w[entry] = cause_r;
            reg [32-1:0] tval_r;
            assign entry_tval_w[entry] = tval_r;
            reg predict_taken_r;
            assign entry_predict_taken_w[entry] = predict_taken_r;
            reg [32-1:0] predict_target_r;
            assign entry_predict_target_w[entry] = predict_target_r;
            reg predict_token_r;
            assign entry_predict_token_w[entry] = predict_token_r;
            reg [3-1:0] predict_provider_r;
            assign entry_predict_provider_w[entry] = predict_provider_r;
            reg predict_alternate_r;
            assign entry_predict_alternate_w[entry] = predict_alternate_r;
            reg [9-1:0] predict_index0_r;
            assign entry_predict_index0_w[entry] = predict_index0_r;
            reg [9-1:0] predict_index1_r;
            assign entry_predict_index1_w[entry] = predict_index1_r;
            reg [9-1:0] predict_index2_r;
            assign entry_predict_index2_w[entry] = predict_index2_r;
            reg [9-1:0] predict_index3_r;
            assign entry_predict_index3_w[entry] = predict_index3_r;
            reg [10-1:0] predict_tag0_r;
            assign entry_predict_tag0_w[entry] = predict_tag0_r;
            reg [10-1:0] predict_tag1_r;
            assign entry_predict_tag1_w[entry] = predict_tag1_r;
            reg [10-1:0] predict_tag2_r;
            assign entry_predict_tag2_w[entry] = predict_tag2_r;
            reg [10-1:0] predict_tag3_r;
            assign entry_predict_tag3_w[entry] = predict_tag3_r;
            reg [12-1:0] predict_base_index_r;
            assign entry_predict_base_index_w[entry] = predict_base_index_r;
            reg [12-1:0] predict_fast_index_r;
            assign entry_predict_fast_index_w[entry] = predict_fast_index_r;
            reg [(128*ISSUE_WIDTH)-1:0] ras_data_r;
            assign entry_ras_data_w[entry] = ras_data_r;
            reg [(ISSUE_WIDTH+1)-1:0] ras_ptr_r;
            assign entry_ras_ptr_w[entry] = ras_ptr_r;
            reg [(ISSUE_WIDTH+2)-1:0] ras_count_r;
            assign entry_ras_count_w[entry] = ras_count_r;
            reg valid_r;
            wire [T-1:0] age_w = ENTRY-age_head_i;
            wire [T:0] occupied_w = N_COUNT-allocate_credit_i;
            assign entry_valid_w[entry] = valid_r && ({1'b0, age_w} < occupied_w);
            reg pending_r;
            assign entry_pending_w[entry] = pending_r;
            reg third_r;
            assign entry_third_w[entry] = third_r;
            reg [3-1:0] countdown_r;
            assign entry_countdown_w[entry] = countdown_r;
            assign serial_pending_w[entry] = entry_valid_w[entry] && (class_r == 3'd7);
            wire canceled_w = cancel_valid_i && (age_w >= cancel_age_w);
            wire retiring_w = valid_r && !({1'b0, age_w} < occupied_w);
            wire accepted_w = pending_r && (channel_tag_w[channel_r] == ENTRY) &&
                channel_valid_w[channel_r] && channel_ready_w[channel_r];
            wire capture0_w = fire_w && (tag0_w == ENTRY);
            wire capture1_w = fire_w && use_pair_w && (tag1_w == ENTRY);
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    valid_r <= 1'b0;
                    pending_r <= 1'b0;
                    third_r <= 1'b0;
                    countdown_r <= 3'd0;
                end else begin
                    if (countdown_r != 0)
                        countdown_r <= countdown_r-1'b1;
                    if (retiring_w || canceled_w)
                        valid_r <= 1'b0;
                    if (accepted_w || canceled_w)
                        pending_r <= 1'b0;
                    if ((third_capture_w && (third_owner_r == ENTRY)) || canceled_w)
                        third_r <= 1'b0;
                    if (capture0_w) begin
                        valid_r <= 1'b1;
                        pending_r <= !(channel0_w == 3'd5 && csr_req_ready_i);
                        third_r <= third_start0_w && !start_wb_w;
                        countdown_r <= d0_class_w == 3'd4 ? 3'd4 :
                            (d0_late_w) ? 3'd2 : 3'd1;
                    end
                    if (capture1_w) begin
                        valid_r <= 1'b1;
                        pending_r <= 1'b1;
                        third_r <= third_start1_w && !start_wb_w;
                        countdown_r <= d1_class_w == 3'd4 ? 3'd4 :
                            (d1_late_w || group_late_w) ? 3'd2 : 3'd1;
                    end
                end
            end
            always @(posedge clk_i) begin
                if (pending_r) begin
                    if (source1_wait_r && pending_source_valid_w[0]) begin
                        src1_r <= pending_source_data_w[0];
                        source1_wait_r <= 1'b0;
                    end
                    if (source2_wait_r && pending_source_valid_w[1]) begin
                        src2_r <= pending_source_data_w[1];
                        source2_wait_r <= 1'b0;
                    end
                end
                if (pending_r && (channel_r == 3'd4))
                    early_r <= 1'b0;
                if (third_capture_w && (third_owner_r == ENTRY))
                    src3_r <= third_data_w;
                if (capture0_w) begin
                    pc_r <= ib_head0_pc_i;
                    instr_r <= ib_head0_instr_i;
                    rd_r <= d0_rd_w;
                    dest_r <= d0_dest_w;
                    class_r <= d0_class_w;
                    channel_r <= channel0_w;
                    src1_r <= value_w[0];
                    src2_r <= value_w[1];
                    src3_r <= third_start0_w && start_wb_w ? fp_wb_data_i : value_w[2];
                    imm_r <= d0_imm_w;
                    late_r <= d0_late_w;
                    source1_tag_r <= q01_tag_w;
                    source2_tag_r <= q02_tag_w;
                    source1_wait_r <= d0_wait1_w;
                    source2_wait_r <= d0_wait2_w;
                    early_r <= early0_w;
                    rm_r <= d0_rm_w;
                    cause_r <= d0_cause_w;
                    tval_r <= d0_tval_w;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_taken_r <= ib_head0_predict_taken_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_target_r <= ib_head0_predict_target_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_token_r <= ib_head0_predict_token_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_provider_r <= ib_head0_predict_provider_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_alternate_r <= ib_head0_predict_alternate_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_index0_r <= ib_head0_predict_index0_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_index1_r <= ib_head0_predict_index1_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_index2_r <= ib_head0_predict_index2_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_index3_r <= ib_head0_predict_index3_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_tag0_r <= ib_head0_predict_tag0_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_tag1_r <= ib_head0_predict_tag1_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_tag2_r <= ib_head0_predict_tag2_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_tag3_r <= ib_head0_predict_tag3_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_base_index_r <= ib_head0_predict_base_index_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        predict_fast_index_r <= ib_head0_predict_fast_index_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        ras_data_r <= ib_head0_ras_data_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        ras_ptr_r <= ib_head0_ras_ptr_i;
                    if ((d0_class_w == 3'd1) || (d0_class_w == 3'd2))
                        ras_count_r <= ib_head0_ras_count_i;
                    if (d0_class_w == 3'd7)
                        src1_r <= {{(B-32){1'b0}}, allocate0_csr_src_o};
                end else if (capture1_w) begin
                    pc_r <= ib_head1_pc_i;
                    instr_r <= ib_head1_instr_i;
                    rd_r <= d1_rd_w;
                    dest_r <= d1_dest_w;
                    class_r <= d1_class_w;
                    channel_r <= channel1_w;
                    src1_r <= value_w[3];
                    src2_r <= value_w[4];
                    src3_r <= third_start1_w && start_wb_w ? fp_wb_data_i : value_w[5];
                    imm_r <= d1_imm_w;
                    late_r <= d1_late_w || group_late_w;
                    source1_tag_r <= raw1_w ? tag0_w : q11_tag_w;
                    source2_tag_r <= raw2_w ? tag0_w : q12_tag_w;
                    source1_wait_r <= raw1_w || d1_wait1_w;
                    source2_wait_r <= raw2_w || d1_wait2_w;
                    early_r <= early1_w;
                    rm_r <= d1_rm_w;
                    cause_r <= d1_cause_w;
                    tval_r <= d1_tval_w;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_taken_r <= ib_head1_predict_taken_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_target_r <= ib_head1_predict_target_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_token_r <= ib_head1_predict_token_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_provider_r <= ib_head1_predict_provider_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_alternate_r <= ib_head1_predict_alternate_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_index0_r <= ib_head1_predict_index0_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_index1_r <= ib_head1_predict_index1_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_index2_r <= ib_head1_predict_index2_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_index3_r <= ib_head1_predict_index3_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_tag0_r <= ib_head1_predict_tag0_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_tag1_r <= ib_head1_predict_tag1_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_tag2_r <= ib_head1_predict_tag2_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_tag3_r <= ib_head1_predict_tag3_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_base_index_r <= ib_head1_predict_base_index_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        predict_fast_index_r <= ib_head1_predict_fast_index_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        ras_data_r <= ib_head1_ras_data_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        ras_ptr_r <= ib_head1_ras_ptr_i;
                    if ((d1_class_w == 3'd1) || (d1_class_w == 3'd2))
                        ras_count_r <= ib_head1_ras_count_i;
                    if (d1_class_w == 3'd7)
                        src1_r <= {{(B-32){1'b0}}, allocate1_csr_src_o};
                end
            end
        end
    endgenerate
    assign execute0_valid_o = (ISSUE_WIDTH > 0) && channel_valid_w[0];
    assign execute0_tag_o = (ISSUE_WIDTH > 0) ?
        channel_tag_w[0] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign execute0_pc_o = (ISSUE_WIDTH > 0) ?
        entry_pc_w[channel_tag_w[0]] : {32{1'b0}};
    assign execute0_instr_o = (ISSUE_WIDTH > 0) ?
        entry_instr_w[channel_tag_w[0]] : {32{1'b0}};
    assign execute0_src1_o = (ISSUE_WIDTH > 0) ?
        entry_src1_w[channel_tag_w[0]][31:0] : {32{1'b0}};
    assign execute0_src2_o = (ISSUE_WIDTH > 0) ?
        entry_src2_w[channel_tag_w[0]][31:0] : {32{1'b0}};
    assign execute0_imm_o = (ISSUE_WIDTH > 0) ?
        entry_imm_w[channel_tag_w[0]] : {32{1'b0}};
    assign execute0_late_o = (ISSUE_WIDTH == 2) ?
        entry_late_w[channel_tag_w[0]] : 1'b0;
    assign execute0_source1_tag_o = (ISSUE_WIDTH == 2) ?
        entry_source1_tag_w[channel_tag_w[0]] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign execute0_source2_tag_o = (ISSUE_WIDTH == 2) ?
        entry_source2_tag_w[channel_tag_w[0]] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign execute0_source1_wait_o = (ISSUE_WIDTH == 2) ?
        entry_source1_wait_w[channel_tag_w[0]] : 1'b0;
    assign execute0_source2_wait_o = (ISSUE_WIDTH == 2) ?
        entry_source2_wait_w[channel_tag_w[0]] : 1'b0;
    assign execute0_predict_taken_o = (ISSUE_WIDTH > 0) ?
        entry_predict_taken_w[channel_tag_w[0]] : 1'b0;
    assign execute0_predict_target_o = (ISSUE_WIDTH > 0) ?
        entry_predict_target_w[channel_tag_w[0]] : {32{1'b0}};
    assign execute0_predict_token_o = (ISSUE_WIDTH > 0) ?
        entry_predict_token_w[channel_tag_w[0]] : 1'b0;
    assign execute0_predict_provider_o = (ISSUE_WIDTH > 0) ?
        entry_predict_provider_w[channel_tag_w[0]] : {3{1'b0}};
    assign execute0_predict_alternate_o = (ISSUE_WIDTH > 0) ?
        entry_predict_alternate_w[channel_tag_w[0]] : 1'b0;
    assign execute0_predict_index0_o = (ISSUE_WIDTH > 0) ?
        entry_predict_index0_w[channel_tag_w[0]] : {9{1'b0}};
    assign execute0_predict_index1_o = (ISSUE_WIDTH > 0) ?
        entry_predict_index1_w[channel_tag_w[0]] : {9{1'b0}};
    assign execute0_predict_index2_o = (ISSUE_WIDTH > 0) ?
        entry_predict_index2_w[channel_tag_w[0]] : {9{1'b0}};
    assign execute0_predict_index3_o = (ISSUE_WIDTH > 0) ?
        entry_predict_index3_w[channel_tag_w[0]] : {9{1'b0}};
    assign execute0_predict_tag0_o = (ISSUE_WIDTH > 0) ?
        entry_predict_tag0_w[channel_tag_w[0]] : {10{1'b0}};
    assign execute0_predict_tag1_o = (ISSUE_WIDTH > 0) ?
        entry_predict_tag1_w[channel_tag_w[0]] : {10{1'b0}};
    assign execute0_predict_tag2_o = (ISSUE_WIDTH > 0) ?
        entry_predict_tag2_w[channel_tag_w[0]] : {10{1'b0}};
    assign execute0_predict_tag3_o = (ISSUE_WIDTH > 0) ?
        entry_predict_tag3_w[channel_tag_w[0]] : {10{1'b0}};
    assign execute0_predict_base_index_o = (ISSUE_WIDTH > 0) ?
        entry_predict_base_index_w[channel_tag_w[0]] : {12{1'b0}};
    assign execute0_predict_fast_index_o = (ISSUE_WIDTH > 0) ?
        entry_predict_fast_index_w[channel_tag_w[0]] : {12{1'b0}};
    assign execute0_ras_data_o = (ISSUE_WIDTH > 0) ?
        entry_ras_data_w[channel_tag_w[0]] : {(128*ISSUE_WIDTH){1'b0}};
    assign execute0_ras_ptr_o = (ISSUE_WIDTH > 0) ?
        entry_ras_ptr_w[channel_tag_w[0]] : {(ISSUE_WIDTH+1){1'b0}};
    assign execute0_ras_count_o = (ISSUE_WIDTH > 0) ?
        entry_ras_count_w[channel_tag_w[0]] : {(ISSUE_WIDTH+2){1'b0}};
    assign execute1_valid_o = (ISSUE_WIDTH > 1) && channel_valid_w[1];
    assign execute1_tag_o = (ISSUE_WIDTH > 1) ?
        channel_tag_w[1] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign execute1_pc_o = (ISSUE_WIDTH > 1) ?
        entry_pc_w[channel_tag_w[1]] : {32{1'b0}};
    assign execute1_instr_o = (ISSUE_WIDTH > 1) ?
        entry_instr_w[channel_tag_w[1]] : {32{1'b0}};
    assign execute1_src1_o = (ISSUE_WIDTH > 1) ?
        entry_src1_w[channel_tag_w[1]][31:0] : {32{1'b0}};
    assign execute1_src2_o = (ISSUE_WIDTH > 1) ?
        entry_src2_w[channel_tag_w[1]][31:0] : {32{1'b0}};
    assign execute1_imm_o = (ISSUE_WIDTH > 1) ?
        entry_imm_w[channel_tag_w[1]] : {32{1'b0}};
    assign execute1_late_o = (ISSUE_WIDTH == 2) ?
        entry_late_w[channel_tag_w[1]] : 1'b0;
    assign execute1_source1_tag_o = (ISSUE_WIDTH == 2) ?
        entry_source1_tag_w[channel_tag_w[1]] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign execute1_source2_tag_o = (ISSUE_WIDTH == 2) ?
        entry_source2_tag_w[channel_tag_w[1]] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign execute1_source1_wait_o = (ISSUE_WIDTH == 2) ?
        entry_source1_wait_w[channel_tag_w[1]] : 1'b0;
    assign execute1_source2_wait_o = (ISSUE_WIDTH == 2) ?
        entry_source2_wait_w[channel_tag_w[1]] : 1'b0;
    assign execute1_predict_taken_o = (ISSUE_WIDTH > 1) ?
        entry_predict_taken_w[channel_tag_w[1]] : 1'b0;
    assign execute1_predict_target_o = (ISSUE_WIDTH > 1) ?
        entry_predict_target_w[channel_tag_w[1]] : {32{1'b0}};
    assign execute1_predict_token_o = (ISSUE_WIDTH > 1) ?
        entry_predict_token_w[channel_tag_w[1]] : 1'b0;
    assign execute1_predict_provider_o = (ISSUE_WIDTH > 1) ?
        entry_predict_provider_w[channel_tag_w[1]] : {3{1'b0}};
    assign execute1_predict_alternate_o = (ISSUE_WIDTH > 1) ?
        entry_predict_alternate_w[channel_tag_w[1]] : 1'b0;
    assign execute1_predict_index0_o = (ISSUE_WIDTH > 1) ?
        entry_predict_index0_w[channel_tag_w[1]] : {9{1'b0}};
    assign execute1_predict_index1_o = (ISSUE_WIDTH > 1) ?
        entry_predict_index1_w[channel_tag_w[1]] : {9{1'b0}};
    assign execute1_predict_index2_o = (ISSUE_WIDTH > 1) ?
        entry_predict_index2_w[channel_tag_w[1]] : {9{1'b0}};
    assign execute1_predict_index3_o = (ISSUE_WIDTH > 1) ?
        entry_predict_index3_w[channel_tag_w[1]] : {9{1'b0}};
    assign execute1_predict_tag0_o = (ISSUE_WIDTH > 1) ?
        entry_predict_tag0_w[channel_tag_w[1]] : {10{1'b0}};
    assign execute1_predict_tag1_o = (ISSUE_WIDTH > 1) ?
        entry_predict_tag1_w[channel_tag_w[1]] : {10{1'b0}};
    assign execute1_predict_tag2_o = (ISSUE_WIDTH > 1) ?
        entry_predict_tag2_w[channel_tag_w[1]] : {10{1'b0}};
    assign execute1_predict_tag3_o = (ISSUE_WIDTH > 1) ?
        entry_predict_tag3_w[channel_tag_w[1]] : {10{1'b0}};
    assign execute1_predict_base_index_o = (ISSUE_WIDTH > 1) ?
        entry_predict_base_index_w[channel_tag_w[1]] : {12{1'b0}};
    assign execute1_predict_fast_index_o = (ISSUE_WIDTH > 1) ?
        entry_predict_fast_index_w[channel_tag_w[1]] : {12{1'b0}};
    assign execute1_ras_data_o = (ISSUE_WIDTH > 1) ?
        entry_ras_data_w[channel_tag_w[1]] : {(128*ISSUE_WIDTH){1'b0}};
    assign execute1_ras_ptr_o = (ISSUE_WIDTH > 1) ?
        entry_ras_ptr_w[channel_tag_w[1]] : {(ISSUE_WIDTH+1){1'b0}};
    assign execute1_ras_count_o = (ISSUE_WIDTH > 1) ?
        entry_ras_count_w[channel_tag_w[1]] : {(ISSUE_WIDTH+2){1'b0}};
    assign mul_req_valid_o = channel_valid_w[2];
    assign mul_req_tag_o = channel_tag_w[2];
    assign mul_req_instr_o = entry_instr_w[channel_tag_w[2]];
    assign mul_req_src1_o = entry_src1_w[channel_tag_w[2]][31:0];
    assign mul_req_src2_o = entry_src2_w[channel_tag_w[2]][31:0];
    assign div_req_valid_o = channel_valid_w[3];
    assign div_req_tag_o = channel_tag_w[3];
    assign div_req_instr_o = entry_instr_w[channel_tag_w[3]];
    assign div_req_src1_o = entry_src1_w[channel_tag_w[3]][31:0];
    assign div_req_src2_o = entry_src2_w[channel_tag_w[3]][31:0];
    assign lsu_req_valid_o = channel_valid_w[4];
    assign lsu_req_tag_o = channel_tag_w[4];
    assign lsu_req_instr_o = entry_instr_w[channel_tag_w[4]];
    assign lsu_req_addr_o = entry_src1_w[channel_tag_w[4]][31:0]+entry_imm_w[channel_tag_w[4]];
    assign lsu_req_store_data_o = entry_src2_w[channel_tag_w[4]];
    assign lsu_req_early_o = entry_early_w[channel_tag_w[4]] && lsu_req_ready_i;
    // Ordered CSR allocation already observes an empty completion queue.
    // Reuse that capture edge at the CSR request register instead of another pending hop.
    wire csr_allocate_w = allocate0_w && channel0_w == 3'd5;
    assign csr_req_valid_o = channel_valid_w[5] || csr_allocate_w;
    assign csr_req_tag_o = csr_allocate_w ? tag0_w : channel_tag_w[5];
    assign csr_req_instr_o = csr_allocate_w ? ib_head0_instr_i : entry_instr_w[channel_tag_w[5]];
    assign csr_req_src_o = csr_allocate_w ? value_w[0][31:0] :
        entry_src1_w[channel_tag_w[5]][31:0];
    assign fp_req_valid_o = (FPU_FORMAT != "NONE") && channel_valid_w[6];
    assign fp_req_tag_o = (FPU_FORMAT != "NONE") ?
        channel_tag_w[6] : {(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3){1'b0}};
    assign fp_req_instr_o = (FPU_FORMAT != "NONE") ?
        entry_instr_w[channel_tag_w[6]] : {32{1'b0}};
    assign fp_req_src1_o = (FPU_FORMAT != "NONE") ?
        entry_src1_w[channel_tag_w[6]] : {((|(FPU_FORMAT ^ "FD")) ? 32 : 64){1'b0}};
    assign fp_req_src2_o = (FPU_FORMAT != "NONE") ?
        entry_src2_w[channel_tag_w[6]] : {((|(FPU_FORMAT ^ "FD")) ? 32 : 64){1'b0}};
    assign fp_req_src3_o = (FPU_FORMAT != "NONE") ?
        entry_src3_w[channel_tag_w[6]] : {((|(FPU_FORMAT ^ "FD")) ? 32 : 64){1'b0}};
    assign fp_req_int_src_o = (FPU_FORMAT != "NONE") ?
        entry_src1_w[channel_tag_w[6]][31:0] : {32{1'b0}};
    assign fp_req_rm_o = (FPU_FORMAT != "NONE") ?
        entry_rm_w[channel_tag_w[6]] : {3{1'b0}};
    assign decode_complete_valid_o = channel_valid_w[7];
    assign decode_complete_tag_o = channel_tag_w[7];
    assign decode_complete_exception_o = 1'b1;
    assign decode_complete_cause_o = entry_cause_w[channel_tag_w[7]];
    assign decode_complete_tval_o = entry_tval_w[channel_tag_w[7]];
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{clk_i, alu0_complete_ready_i, alu1_complete_ready_i,
        rst_n_i,
        age_head_i,
        cancel_valid_i,
        cancel_tag_i,
        csr_fs_i,
        csr_frm_i,
        ib_head0_valid_i,
        ib_head0_pc_i,
        ib_head0_instr_i,
        ib_head0_error_i,
        ib_head0_candidates_i,
        ib_head0_predict_taken_i,
        ib_head0_predict_target_i,
        ib_head0_predict_token_i,
        ib_head0_predict_provider_i,
        ib_head0_predict_alternate_i,
        ib_head0_predict_index0_i,
        ib_head0_predict_index1_i,
        ib_head0_predict_index2_i,
        ib_head0_predict_index3_i,
        ib_head0_predict_tag0_i,
        ib_head0_predict_tag1_i,
        ib_head0_predict_tag2_i,
        ib_head0_predict_tag3_i,
        ib_head0_predict_base_index_i,
        ib_head0_predict_fast_index_i,
        ib_head0_ras_data_i,
        ib_head0_ras_ptr_i,
        ib_head0_ras_count_i,
        ib_head1_valid_i,
        ib_head1_pc_i,
        ib_head1_instr_i,
        ib_head1_error_i,
        ib_head1_candidates_i,
        ib_head1_predict_taken_i,
        ib_head1_predict_target_i,
        ib_head1_predict_token_i,
        ib_head1_predict_provider_i,
        ib_head1_predict_alternate_i,
        ib_head1_predict_index0_i,
        ib_head1_predict_index1_i,
        ib_head1_predict_index2_i,
        ib_head1_predict_index3_i,
        ib_head1_predict_tag0_i,
        ib_head1_predict_tag1_i,
        ib_head1_predict_tag2_i,
        ib_head1_predict_tag3_i,
        ib_head1_predict_base_index_i,
        ib_head1_predict_fast_index_i,
        ib_head1_ras_data_i,
        ib_head1_ras_ptr_i,
        ib_head1_ras_count_i,
        id_data0_i,
        id_data1_i,
        id_data2_i,
        id_data3_i,
        wb0_valid_i,
        wb0_rd_i,
        wb0_data_i,
        wb0_tag_i,
        wb1_valid_i,
        wb1_rd_i,
        wb1_data_i,
        wb1_tag_i,
        fp_read0_data_i,
        fp_read1_data_i,
        fp_read2_data_i,
        fp_wb_valid_i,
        fp_wb_rd_i,
        fp_wb_data_i,
        fp_wb_tag_i,
        allocate_credit_i,
        allocate_ready_i,
        source0_ready_i,
        source0_data_i,
        source1_ready_i,
        source1_data_i,
        source2_ready_i,
        source2_data_i,
        source3_ready_i,
        source3_data_i,
        source4_ready_i,
        source4_data_i,
        execute0_ready_i,
        execute1_ready_i,
        mul_req_ready_i,
        div_req_ready_i,
        lsu_req_ready_i,
        csr_req_ready_i,
        fp_req_ready_i,
        decode_complete_ready_i};
    /* verilator lint_on UNUSEDSIGNAL */
    assign issue_hpm_o = {
                !ib_head0_valid_i && allocate_credit_i != 0 && !cancel_valid_i,
                1'b0, observe_div_w, observe_load_w,
                observe_single_w && !ib_head1_valid_i,
                !observe_raw_w && !observe_structure_w && observe_type_w,
                !observe_raw_w && observe_structure_w, observe_raw_w};
    wire observe_single_w = ISSUE_WIDTH == 2 && fire_w && !use_pair_w;
    wire observe_raw_w = observe_single_w && ib_head1_valid_i && !raw_pair_w;
    wire observe_structure_w = observe_single_w && ib_head1_valid_i &&
        ((allocate_credit_i < 2) || !pair_capacity_w || !d1_sources_w);
    wire observe_type_w = observe_single_w && ib_head1_valid_i && !types_pair_w;
    wire observe_load_w = ib_head0_valid_i && !head_ready_w &&
        ((d0_wait1_w && entry_class_w[q01_tag_w] == 3'd3) ||
        (d0_wait2_w && entry_class_w[q02_tag_w] == 3'd3));
    wire observe_div_w = ib_head0_valid_i && !head_ready_w &&
        ((d0_wait1_w && entry_class_w[q01_tag_w] == 3'd5) ||
        (d0_wait2_w && entry_class_w[q02_tag_w] == 3'd5) ||
        (d0_class_w == 3'd5 && !div_req_ready_i));
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            issue_pair_cause_o <= 3'b0;
            issue_wait_o <= 1'b0;
        end else begin

            issue_pair_cause_o <= observe_raw_w ? 3'd1 :
                observe_structure_w ? 3'd2 : observe_type_w ? 3'd3 :
                (observe_single_w && !ib_head1_valid_i) ? 3'd4 : 3'd0;
            issue_wait_o <= ib_head0_valid_i && !fire_w;
        end
    end
endmodule
