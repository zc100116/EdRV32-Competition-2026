// File: edrv32_cpu2_branch.v
// Spec: cpu-v2-spec 3.2-3.5, 5.2-5.3, 6.1; interface-freeze RAS recovery.
// Description: Branch operand capture shares the ALU pipeline implementation, with domain-local
// compare operations; one EX target adder serves JALR and one MEM adder serves late branches.
// Clock domain: clk_sys.
module edrv32_cpu2_branch #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Program-tag metadata follows execute acceptance through local operand waiting.
    input wire lsu_complete_device_i,
    // Frozen early return: data was captured locally by LSU before operand capture.
    input wire early_resp_valid_i,
    input wire [(FPU_FORMAT=="FD" ? 4 : FPU_FORMAT=="F" ? 3 : 2)-1:0] early_resp_tag_i,
    input wire early_resp_hit_i,
    input wire [31:0] early_resp_data_i,
    input wire wb0_valid_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] wb0_tag_i,
    input wire [31:0] wb0_data_i,
    input wire wb1_valid_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] wb1_tag_i,
    input wire [31:0] wb1_data_i,
    input wire clk_i,
    input wire rst_n_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] cancel_tag_i,
    input wire execute0_valid_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute0_tag_i,
    input wire [32-1:0] execute0_pc_i,
    input wire [32-1:0] execute0_instr_i,
    input wire [32-1:0] execute0_src1_i,
    input wire [32-1:0] execute0_src2_i,
    input wire [32-1:0] execute0_imm_i,
    input wire execute0_late_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute0_source1_tag_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute0_source2_tag_i,
    input wire execute0_source1_wait_i,
    input wire execute0_source2_wait_i,
    input wire execute0_predict_taken_i,
    input wire [32-1:0] execute0_predict_target_i,
    input wire execute0_predict_token_i,
    input wire [3-1:0] execute0_predict_provider_i,
    input wire execute0_predict_alternate_i,
    input wire [9-1:0] execute0_predict_index0_i,
    input wire [9-1:0] execute0_predict_index1_i,
    input wire [9-1:0] execute0_predict_index2_i,
    input wire [9-1:0] execute0_predict_index3_i,
    input wire [10-1:0] execute0_predict_tag0_i,
    input wire [10-1:0] execute0_predict_tag1_i,
    input wire [10-1:0] execute0_predict_tag2_i,
    input wire [10-1:0] execute0_predict_tag3_i,
    input wire [12-1:0] execute0_predict_base_index_i,
    input wire [12-1:0] execute0_predict_fast_index_i,
    input wire [(128*ISSUE_WIDTH)-1:0] execute0_ras_data_i,
    input wire [(ISSUE_WIDTH+1)-1:0] execute0_ras_ptr_i,
    input wire [(ISSUE_WIDTH+2)-1:0] execute0_ras_count_i,
    output wire execute0_ready_o,
    input wire execute1_valid_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute1_tag_i,
    input wire [32-1:0] execute1_pc_i,
    input wire [32-1:0] execute1_instr_i,
    input wire [32-1:0] execute1_src1_i,
    input wire [32-1:0] execute1_src2_i,
    input wire [32-1:0] execute1_imm_i,
    input wire execute1_late_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute1_source1_tag_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] execute1_source2_tag_i,
    input wire execute1_source1_wait_i,
    input wire execute1_source2_wait_i,
    input wire execute1_predict_taken_i,
    input wire [32-1:0] execute1_predict_target_i,
    input wire execute1_predict_token_i,
    input wire [3-1:0] execute1_predict_provider_i,
    input wire execute1_predict_alternate_i,
    input wire [9-1:0] execute1_predict_index0_i,
    input wire [9-1:0] execute1_predict_index1_i,
    input wire [9-1:0] execute1_predict_index2_i,
    input wire [9-1:0] execute1_predict_index3_i,
    input wire [10-1:0] execute1_predict_tag0_i,
    input wire [10-1:0] execute1_predict_tag1_i,
    input wire [10-1:0] execute1_predict_tag2_i,
    input wire [10-1:0] execute1_predict_tag3_i,
    input wire [12-1:0] execute1_predict_base_index_i,
    input wire [12-1:0] execute1_predict_fast_index_i,
    input wire [(128*ISSUE_WIDTH)-1:0] execute1_ras_data_i,
    input wire [(ISSUE_WIDTH+1)-1:0] execute1_ras_ptr_i,
    input wire [(ISSUE_WIDTH+2)-1:0] execute1_ras_count_i,
    output wire execute1_ready_o,
    input wire alu0_complete_valid_i,
    input wire alu0_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] alu0_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_i,
    input wire alu1_complete_valid_i,
    input wire alu1_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] alu1_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_i,
    input wire branch_complete_valid_i,
    input wire branch_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] branch_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_i,
    input wire mul_complete_valid_i,
    input wire mul_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] mul_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] mul_complete_data_i,
    input wire div_complete_valid_i,
    input wire div_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] div_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] div_complete_data_i,
    input wire lsu_complete_valid_i,
    input wire lsu_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] lsu_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_complete_data_i,
    input wire csr_complete_valid_i,
    input wire csr_complete_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] csr_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] csr_complete_data_i,
    input wire fp_resp_valid_i,
    input wire fp_resp_ready_i,
    input wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] fp_resp_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_resp_data_i,
    output wire branch_complete_valid_o,
    output wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] branch_complete_tag_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_o,
    output wire [5-1:0] branch_complete_flags_o,
    output wire branch_complete_exception_o,
    output wire [4-1:0] branch_complete_cause_o,
    output wire [32-1:0] branch_complete_tval_o,
    output wire [32-1:0] branch_complete_next_pc_o,
    output reg ex_predict_train_valid_o,
    output reg [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] ex_predict_train_tag_o,
    output reg [32-1:0] ex_predict_train_pc_o,
    output reg ex_predict_train_taken_o,
    output reg [32-1:0] ex_predict_train_target_o,
    output reg [3-1:0] ex_predict_train_type_o,
    output wire ex_predict_train_token_o,
    output wire [3-1:0] ex_predict_train_provider_o,
    output wire ex_predict_train_alternate_o,
    output wire ex_predict_train_prediction_o,
    output wire [9-1:0] ex_predict_train_index0_o,
    output wire [9-1:0] ex_predict_train_index1_o,
    output wire [9-1:0] ex_predict_train_index2_o,
    output wire [9-1:0] ex_predict_train_index3_o,
    output wire [10-1:0] ex_predict_train_tag0_o,
    output wire [10-1:0] ex_predict_train_tag1_o,
    output wire [10-1:0] ex_predict_train_tag2_o,
    output wire [10-1:0] ex_predict_train_tag3_o,
    output wire [12-1:0] ex_predict_train_base_index_o,
    output reg [12-1:0] ex_predict_train_fast_index_o,
    output wire mem_predict_train_valid_o,
    output wire [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] mem_predict_train_tag_o,
    output wire [32-1:0] mem_predict_train_pc_o,
    output wire mem_predict_train_taken_o,
    output wire [32-1:0] mem_predict_train_target_o,
    output wire [3-1:0] mem_predict_train_type_o,
    output wire mem_predict_train_token_o,
    output wire [3-1:0] mem_predict_train_provider_o,
    output wire mem_predict_train_alternate_o,
    output wire mem_predict_train_prediction_o,
    output wire [9-1:0] mem_predict_train_index0_o,
    output wire [9-1:0] mem_predict_train_index1_o,
    output wire [9-1:0] mem_predict_train_index2_o,
    output wire [9-1:0] mem_predict_train_index3_o,
    output wire [10-1:0] mem_predict_train_tag0_o,
    output wire [10-1:0] mem_predict_train_tag1_o,
    output wire [10-1:0] mem_predict_train_tag2_o,
    output wire [10-1:0] mem_predict_train_tag3_o,
    output wire [12-1:0] mem_predict_train_base_index_o,
    output wire [12-1:0] mem_predict_train_fast_index_o,
    output reg branch_redirect_valid_o,
    output reg [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] branch_redirect_tag_o,
    output reg [32-1:0] branch_redirect_pc_o,
    output reg [(128*ISSUE_WIDTH)-1:0] branch_redirect_ras_data_o,
    output reg [(ISSUE_WIDTH+1)-1:0] branch_redirect_ras_ptr_o,
    output reg [(ISSUE_WIDTH+2)-1:0] branch_redirect_ras_count_o,
    output reg branch_redirect_ras_pop_o,
    output reg branch_redirect_ras_push_o,
    output reg [32-1:0] branch_redirect_link_o,
    // I06: registered recovery observation aligned with branch_redirect_valid.
    output reg [31:0] trace_branch_pc_o,
    output reg [1:0] trace_branch_stage_o,
    output reg [1:0] trace_branch_cause_o,
    output wire [1:0] debug_mem_valid_o
);
    localparam T = FPU_FORMAT=="NONE" ? 2 : FPU_FORMAT=="F" ? 3 : 4;
    localparam B = FPU_FORMAT=="FD" ? 64 : 32;
    localparam N = 2**T;
    reg ex_predict_train_token_r;
    assign ex_predict_train_token_o = (ISSUE_WIDTH == 2) ? ex_predict_train_token_r : 1'b0;
    reg [3-1:0] ex_predict_train_provider_r;
    assign ex_predict_train_provider_o =
        (ISSUE_WIDTH == 2) ? ex_predict_train_provider_r : {3{1'b0}};
    reg ex_predict_train_alternate_r;
    assign ex_predict_train_alternate_o = (ISSUE_WIDTH == 2) ? ex_predict_train_alternate_r : 1'b0;
    reg ex_predict_train_prediction_r;
    assign ex_predict_train_prediction_o =
        (ISSUE_WIDTH == 2) ? ex_predict_train_prediction_r : 1'b0;
    reg [9-1:0] ex_predict_train_index0_r;
    assign ex_predict_train_index0_o = (ISSUE_WIDTH == 2) ? ex_predict_train_index0_r : {9{1'b0}};
    reg [9-1:0] ex_predict_train_index1_r;
    assign ex_predict_train_index1_o = (ISSUE_WIDTH == 2) ? ex_predict_train_index1_r : {9{1'b0}};
    reg [9-1:0] ex_predict_train_index2_r;
    assign ex_predict_train_index2_o = (ISSUE_WIDTH == 2) ? ex_predict_train_index2_r : {9{1'b0}};
    reg [9-1:0] ex_predict_train_index3_r;
    assign ex_predict_train_index3_o = (ISSUE_WIDTH == 2) ? ex_predict_train_index3_r : {9{1'b0}};
    reg [10-1:0] ex_predict_train_tag0_r;
    assign ex_predict_train_tag0_o = (ISSUE_WIDTH == 2) ? ex_predict_train_tag0_r : {10{1'b0}};
    reg [10-1:0] ex_predict_train_tag1_r;
    assign ex_predict_train_tag1_o = (ISSUE_WIDTH == 2) ? ex_predict_train_tag1_r : {10{1'b0}};
    reg [10-1:0] ex_predict_train_tag2_r;
    assign ex_predict_train_tag2_o = (ISSUE_WIDTH == 2) ? ex_predict_train_tag2_r : {10{1'b0}};
    reg [10-1:0] ex_predict_train_tag3_r;
    assign ex_predict_train_tag3_o = (ISSUE_WIDTH == 2) ? ex_predict_train_tag3_r : {10{1'b0}};
    reg [12-1:0] ex_predict_train_base_index_r;
    assign ex_predict_train_base_index_o =
        (ISSUE_WIDTH == 2) ? ex_predict_train_base_index_r : {12{1'b0}};
    reg mem_predict_train_valid_r;
    assign mem_predict_train_valid_o = (ISSUE_WIDTH == 2) ? mem_predict_train_valid_r : 1'b0;
    reg [(FPU_FORMAT>"FD"?2:FPU_FORMAT>"F"?4:3)-1:0] mem_predict_train_tag_r;
    assign mem_predict_train_tag_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_tag_r : {T{1'b0}};
    reg [32-1:0] mem_predict_train_pc_r;
    assign mem_predict_train_pc_o = (ISSUE_WIDTH == 2) ? mem_predict_train_pc_r : {32{1'b0}};
    reg mem_predict_train_taken_r;
    assign mem_predict_train_taken_o = (ISSUE_WIDTH == 2) ? mem_predict_train_taken_r : 1'b0;
    reg [32-1:0] mem_predict_train_target_r;
    assign mem_predict_train_target_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_target_r : {32{1'b0}};
    reg [3-1:0] mem_predict_train_type_r;
    assign mem_predict_train_type_o = (ISSUE_WIDTH == 2) ? mem_predict_train_type_r : {3{1'b0}};
    reg mem_predict_train_token_r;
    assign mem_predict_train_token_o = (ISSUE_WIDTH == 2) ? mem_predict_train_token_r : 1'b0;
    reg [3-1:0] mem_predict_train_provider_r;
    assign mem_predict_train_provider_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_provider_r : {3{1'b0}};
    reg mem_predict_train_alternate_r;
    assign mem_predict_train_alternate_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_alternate_r : 1'b0;
    reg mem_predict_train_prediction_r;
    assign mem_predict_train_prediction_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_prediction_r : 1'b0;
    reg [9-1:0] mem_predict_train_index0_r;
    assign mem_predict_train_index0_o = (ISSUE_WIDTH == 2) ? mem_predict_train_index0_r : {9{1'b0}};
    reg [9-1:0] mem_predict_train_index1_r;
    assign mem_predict_train_index1_o = (ISSUE_WIDTH == 2) ? mem_predict_train_index1_r : {9{1'b0}};
    reg [9-1:0] mem_predict_train_index2_r;
    assign mem_predict_train_index2_o = (ISSUE_WIDTH == 2) ? mem_predict_train_index2_r : {9{1'b0}};
    reg [9-1:0] mem_predict_train_index3_r;
    assign mem_predict_train_index3_o = (ISSUE_WIDTH == 2) ? mem_predict_train_index3_r : {9{1'b0}};
    reg [10-1:0] mem_predict_train_tag0_r;
    assign mem_predict_train_tag0_o = (ISSUE_WIDTH == 2) ? mem_predict_train_tag0_r : {10{1'b0}};
    reg [10-1:0] mem_predict_train_tag1_r;
    assign mem_predict_train_tag1_o = (ISSUE_WIDTH == 2) ? mem_predict_train_tag1_r : {10{1'b0}};
    reg [10-1:0] mem_predict_train_tag2_r;
    assign mem_predict_train_tag2_o = (ISSUE_WIDTH == 2) ? mem_predict_train_tag2_r : {10{1'b0}};
    reg [10-1:0] mem_predict_train_tag3_r;
    assign mem_predict_train_tag3_o = (ISSUE_WIDTH == 2) ? mem_predict_train_tag3_r : {10{1'b0}};
    reg [12-1:0] mem_predict_train_base_index_r;
    assign mem_predict_train_base_index_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_base_index_r : {12{1'b0}};
    reg [12-1:0] mem_predict_train_fast_index_r;
    assign mem_predict_train_fast_index_o =
        (ISSUE_WIDTH == 2) ? mem_predict_train_fast_index_r : {12{1'b0}};
    wire [32-1:0] meta_pc_w [0:N-1];
    wire [32-1:0] meta_instr_w [0:N-1];
    wire [32-1:0] meta_src1_w [0:N-1];
    wire [32-1:0] meta_imm_w [0:N-1];
    wire meta_late_w [0:N-1];
    wire meta_predict_taken_w [0:N-1];
    wire [32-1:0] meta_predict_target_w [0:N-1];
    wire meta_predict_token_w [0:N-1];
    wire [3-1:0] meta_predict_provider_w [0:N-1];
    wire meta_predict_alternate_w [0:N-1];
    wire [9-1:0] meta_predict_index0_w [0:N-1];
    wire [9-1:0] meta_predict_index1_w [0:N-1];
    wire [9-1:0] meta_predict_index2_w [0:N-1];
    wire [9-1:0] meta_predict_index3_w [0:N-1];
    wire [10-1:0] meta_predict_tag0_w [0:N-1];
    wire [10-1:0] meta_predict_tag1_w [0:N-1];
    wire [10-1:0] meta_predict_tag2_w [0:N-1];
    wire [10-1:0] meta_predict_tag3_w [0:N-1];
    wire [12-1:0] meta_predict_base_index_w [0:N-1];
    wire [12-1:0] meta_predict_fast_index_w [0:N-1];
    wire [(128*ISSUE_WIDTH)-1:0] meta_ras_data_w [0:N-1];
    wire [(ISSUE_WIDTH+1)-1:0] meta_ras_ptr_w [0:N-1];
    wire [(ISSUE_WIDTH+2)-1:0] meta_ras_count_w [0:N-1];
    wire meta_seen_w [0:N-1];
    wire [32-1:0] meta_resolved_target_w [0:N-1];
    wire [32-1:0] meta_resolved_next_w [0:N-1];
    wire [32-1:0] meta_resolved_link_w [0:N-1];
    wire meta_resolved_exception_w [0:N-1];
    wire [31:0] compare0_instr_w;
    wire compare0_valid_w;
    wire compare0_ready_w;
    wire [T-1:0] compare0_tag_w;
    wire [B-1:0] compare0_data_w;
    wire [4:0] compare0_flags_w;
    wire compare0_exception_w;
    wire [3:0] compare0_cause_w;
    wire [31:0] compare0_tval_w;
    wire [T-1:0] compare0_age_w = compare0_tag_w - age_head_i;
    wire [2:0] condition0_w = execute0_instr_i[14:12];
    // XOR implements EQ/NE; SLT and SLTU implement the signed/unsigned branch pairs.
    assign compare0_instr_w = {17'd0,
        (execute0_instr_i[6:0] != 7'h63) ? 3'd4 :
        (condition0_w[2:1] == 2'd0) ? 3'd4 :
        condition0_w[1] ? 3'd3 : 3'd2, 5'd0, 7'h33};
    wire [31:0] compare1_instr_w;
    wire compare1_valid_w;
    wire compare1_ready_w;
    wire [T-1:0] compare1_tag_w;
    wire [B-1:0] compare1_data_w;
    wire [4:0] compare1_flags_w;
    wire compare1_exception_w;
    wire [3:0] compare1_cause_w;
    wire [31:0] compare1_tval_w;
    wire [T-1:0] compare1_age_w = compare1_tag_w - age_head_i;
    wire [2:0] condition1_w = execute1_instr_i[14:12];
    // XOR implements EQ/NE; SLT and SLTU implement the signed/unsigned branch pairs.
    assign compare1_instr_w = {17'd0,
        (execute1_instr_i[6:0] != 7'h63) ? 3'd4 :
        (condition1_w[2:1] == 2'd0) ? 3'd4 :
        condition1_w[1] ? 3'd3 : 3'd2, 5'd0, 7'h33};
    genvar entry;
    generate
        for (entry=0; entry<N; entry=entry+1) begin : g_entry
            localparam [T-1:0] ENTRY = entry;
            reg [32-1:0] pc_r;
            assign meta_pc_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_pc_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_pc_i : pc_r;
            reg [32-1:0] instr_r;
            assign meta_instr_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_instr_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_instr_i : instr_r;
            reg [32-1:0] src1_r;
            assign meta_src1_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_src1_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_src1_i : src1_r;
            reg [32-1:0] imm_r;
            assign meta_imm_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_imm_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_imm_i : imm_r;
            reg late_r;
            assign meta_late_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_late_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_late_i : late_r;
            reg predict_taken_r;
            assign meta_predict_taken_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_taken_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_taken_i : predict_taken_r;
            reg [32-1:0] predict_target_r;
            assign meta_predict_target_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_target_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_target_i : predict_target_r;
            reg predict_token_r;
            assign meta_predict_token_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_token_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_token_i : predict_token_r;
            reg [3-1:0] predict_provider_r;
            assign meta_predict_provider_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_provider_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_provider_i : predict_provider_r;
            reg predict_alternate_r;
            assign meta_predict_alternate_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_alternate_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_alternate_i : predict_alternate_r;
            reg [9-1:0] predict_index0_r;
            assign meta_predict_index0_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_index0_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_index0_i : predict_index0_r;
            reg [9-1:0] predict_index1_r;
            assign meta_predict_index1_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_index1_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_index1_i : predict_index1_r;
            reg [9-1:0] predict_index2_r;
            assign meta_predict_index2_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_index2_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_index2_i : predict_index2_r;
            reg [9-1:0] predict_index3_r;
            assign meta_predict_index3_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_index3_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_index3_i : predict_index3_r;
            reg [10-1:0] predict_tag0_r;
            assign meta_predict_tag0_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_tag0_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_tag0_i : predict_tag0_r;
            reg [10-1:0] predict_tag1_r;
            assign meta_predict_tag1_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_tag1_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_tag1_i : predict_tag1_r;
            reg [10-1:0] predict_tag2_r;
            assign meta_predict_tag2_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_tag2_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_tag2_i : predict_tag2_r;
            reg [10-1:0] predict_tag3_r;
            assign meta_predict_tag3_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_tag3_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_tag3_i : predict_tag3_r;
            reg [12-1:0] predict_base_index_r;
            assign meta_predict_base_index_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_base_index_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_base_index_i : predict_base_index_r;
            reg [12-1:0] predict_fast_index_r;
            assign meta_predict_fast_index_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_predict_fast_index_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_predict_fast_index_i : predict_fast_index_r;
            reg [(128*ISSUE_WIDTH)-1:0] ras_data_r;
            assign meta_ras_data_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_ras_data_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_ras_data_i : ras_data_r;
            reg [(ISSUE_WIDTH+1)-1:0] ras_ptr_r;
            assign meta_ras_ptr_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_ras_ptr_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_ras_ptr_i : ras_ptr_r;
            reg [(ISSUE_WIDTH+2)-1:0] ras_count_r;
            assign meta_ras_count_w[entry] =
                (execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ?
                execute0_ras_count_i :
                (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)) ?
                execute1_ras_count_i : ras_count_r;
            reg [32-1:0] resolved_target_r;
            assign meta_resolved_target_w[entry] = resolved_target_r;
            reg [32-1:0] resolved_next_r;
            assign meta_resolved_next_w[entry] = resolved_next_r;
            reg [32-1:0] resolved_link_r;
            assign meta_resolved_link_w[entry] = resolved_link_r;
            reg resolved_exception_r;
            assign meta_resolved_exception_w[entry] = resolved_exception_r;
            reg seen_r;
            assign meta_seen_w[entry] = seen_r &&
                !(execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) &&
                !(execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY));
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    seen_r <= 1'b0;
                else if ((ex_resolve_w && (ex_tag_w == ENTRY)) ||
                    (mem_resolve_w && (mem_tag_w == ENTRY)))
                    seen_r <= 1'b1;
                else if ((execute0_valid_i && execute0_ready_o && (execute0_tag_i == ENTRY)) ||
                    (execute1_valid_i && execute1_ready_o && (execute1_tag_i == ENTRY)))
                    seen_r <= 1'b0;
            end
            always @(posedge clk_i) begin
                if (ex_resolve_w && (ex_tag_w == ENTRY)) begin
                    resolved_target_r <= ex_target_w;
                    resolved_next_r <= ex_next_w;
                    resolved_link_r <= ex_link_w;
                    resolved_exception_r <= ex_exception_w;
                end
                if (mem_resolve_w && (mem_tag_w == ENTRY)) begin
                    resolved_target_r <= mem_target_w;
                    resolved_next_r <= mem_next_w;
                    resolved_link_r <= mem_link_w;
                    resolved_exception_r <= mem_exception_w;
                end
                if (execute0_valid_i && execute0_ready_o &&
                    (execute0_tag_i == ENTRY)) begin
                    pc_r <= execute0_pc_i;
                    instr_r <= execute0_instr_i;
                    src1_r <= execute0_src1_i;
                    imm_r <= execute0_imm_i;
                    late_r <= execute0_late_i;
                    predict_taken_r <= execute0_predict_taken_i;
                    predict_target_r <= execute0_predict_target_i;
                    predict_token_r <= execute0_predict_token_i;
                    predict_provider_r <= execute0_predict_provider_i;
                    predict_alternate_r <= execute0_predict_alternate_i;
                    predict_index0_r <= execute0_predict_index0_i;
                    predict_index1_r <= execute0_predict_index1_i;
                    predict_index2_r <= execute0_predict_index2_i;
                    predict_index3_r <= execute0_predict_index3_i;
                    predict_tag0_r <= execute0_predict_tag0_i;
                    predict_tag1_r <= execute0_predict_tag1_i;
                    predict_tag2_r <= execute0_predict_tag2_i;
                    predict_tag3_r <= execute0_predict_tag3_i;
                    predict_base_index_r <= execute0_predict_base_index_i;
                    predict_fast_index_r <= execute0_predict_fast_index_i;
                    ras_data_r <= execute0_ras_data_i;
                    ras_ptr_r <= execute0_ras_ptr_i;
                    ras_count_r <= execute0_ras_count_i;
                end else if (execute1_valid_i && execute1_ready_o &&
                    (execute1_tag_i == ENTRY)) begin
                    pc_r <= execute1_pc_i;
                    instr_r <= execute1_instr_i;
                    src1_r <= execute1_src1_i;
                    imm_r <= execute1_imm_i;
                    late_r <= execute1_late_i;
                    predict_taken_r <= execute1_predict_taken_i;
                    predict_target_r <= execute1_predict_target_i;
                    predict_token_r <= execute1_predict_token_i;
                    predict_provider_r <= execute1_predict_provider_i;
                    predict_alternate_r <= execute1_predict_alternate_i;
                    predict_index0_r <= execute1_predict_index0_i;
                    predict_index1_r <= execute1_predict_index1_i;
                    predict_index2_r <= execute1_predict_index2_i;
                    predict_index3_r <= execute1_predict_index3_i;
                    predict_tag0_r <= execute1_predict_tag0_i;
                    predict_tag1_r <= execute1_predict_tag1_i;
                    predict_tag2_r <= execute1_predict_tag2_i;
                    predict_tag3_r <= execute1_predict_tag3_i;
                    predict_base_index_r <= execute1_predict_base_index_i;
                    predict_fast_index_r <= execute1_predict_fast_index_i;
                    ras_data_r <= execute1_ras_data_i;
                    ras_ptr_r <= execute1_ras_ptr_i;
                    ras_count_r <= execute1_ras_count_i;
                end
            end
        end
    endgenerate
    generate
        if (ISSUE_WIDTH > 0) begin : g_pipe0
            reg skid_valid_r;
            reg [T-1:0] skid_tag_r;
            reg [31:0] skid_data_r;
            reg mem_valid_r;
            assign debug_mem_valid_o[0] = mem_valid_r;
            reg [T-1:0] mem_tag_r;
            reg [31:0] mem_instr_r;
            reg [31:0] mem_src1_r;
            reg [31:0] mem_src2_r;
            reg [31:0] mem_imm_r;
            reg [T-1:0] mem_source1_tag_r;
            reg [T-1:0] mem_source2_tag_r;
            reg mem_wait1_r;
            reg mem_wait2_r;
            wire ex_valid_r = execute0_valid_i && execute0_ready_o && !input_cancel_w;
            wire ex_late_r = (ISSUE_WIDTH == 2) && execute0_late_i;
            wire [T-1:0] ex_tag_r = execute0_tag_i;
            wire [32-1:0] ex_pc_r = execute0_pc_i;
            wire [32-1:0] ex_instr_r = compare0_instr_w;
            wire [32-1:0] ex_src1_r = (execute0_instr_i[6:0] == 7'h63) ?
                        execute0_src1_i : 32'd0;
            wire [32-1:0] ex_src2_r = (execute0_instr_i[6:0] == 7'h63) ?
                        execute0_src2_i : 32'd0;
            wire [32-1:0] ex_imm_r = execute0_imm_i;
            wire [T-1:0] ex_source1_tag_r = execute0_source1_tag_i;
            wire [T-1:0] ex_source2_tag_r = execute0_source2_tag_i;
            wire ex_wait1_r = (ISSUE_WIDTH == 2) && execute0_source1_wait_i;
            wire ex_wait2_r = (ISSUE_WIDTH == 2) && execute0_source2_wait_i;
            wire [T-1:0] ex_age_w = ex_tag_r - age_head_i;
            wire ex_cancel_w = cancel_valid_i && (ex_age_w >= cancel_age_w);
            wire [T-1:0] skid_age_w = skid_tag_r - age_head_i;
            wire skid_cancel_w = skid_valid_r && cancel_valid_i && (skid_age_w >= cancel_age_w);
            wire [T-1:0] mem_age_w = mem_tag_r - age_head_i;
            wire mem_cancel_w = mem_valid_r && cancel_valid_i && (mem_age_w >= cancel_age_w);
            wire [T-1:0] input_age_w = execute0_tag_i - age_head_i;
            wire input_cancel_w = execute0_valid_i && cancel_valid_i &&
                (input_age_w >= cancel_age_w);
            wire [T-1:0] cancel_age_w = cancel_tag_i - age_head_i;
            wire ex_early_w = ex_valid_r && !ex_late_r;
            wire mem_ready_w = mem_valid_r && !mem_wait1_r && !mem_wait2_r;
            assign execute0_ready_o = ex_late_r ? !mem_valid_r : !skid_valid_r;
            wire transfer_w = ex_valid_r && ex_late_r && !mem_valid_r;
            reg lock_valid_r;
            reg [T-1:0] lock_tag_r;
            wire candidate_skid_w = skid_valid_r &&
                (!mem_ready_w || (skid_age_w < mem_age_w));
            wire candidate_mem_w = mem_ready_w && !candidate_skid_w &&
                (!ex_early_w || (mem_age_w < ex_age_w));
            wire candidate_ex_w = ex_early_w && !candidate_skid_w && !candidate_mem_w;
            wire select_skid_w = lock_valid_r ?
                (skid_valid_r && (skid_tag_r == lock_tag_r)) : candidate_skid_w;
            wire select_mem_w = lock_valid_r ?
                (mem_ready_w && (mem_tag_r == lock_tag_r)) : candidate_mem_w;
            wire select_ex_w = lock_valid_r ?
                (ex_early_w && (ex_tag_r == lock_tag_r)) : candidate_ex_w;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    lock_valid_r <= 1'b0;
                else if (compare0_valid_w && compare0_ready_w)
                    lock_valid_r <= 1'b0;
                else if (lock_valid_r && cancel_valid_i &&
                    ((lock_tag_r-age_head_i) >= cancel_age_w))
                    lock_valid_r <= 1'b0;
                else if (compare0_valid_w &&
                    !(cancel_valid_i && compare0_age_w >= cancel_age_w))
                    lock_valid_r <= 1'b1;
            end
            always @(posedge clk_i) begin
                if (compare0_valid_w && !compare0_ready_w)
                    lock_tag_r <= compare0_tag_w;
            end
            wire ex_done_w = select_ex_w && compare0_ready_w;
            wire skid_done_w = select_skid_w && compare0_ready_w;
            wire mem_done_w = select_mem_w && compare0_ready_w;
            wire stash_w = ex_early_w && !skid_valid_r && !ex_done_w;
            wire ex_hit1_w;
            wire [31:0] ex_capture1_w;
            wire ex_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source1_tag_r);
            wire ex_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source1_tag_r);
            assign ex_hit1_w = ex_source1_early_w || ex_source1_0_w ||
                ex_source1_1_w ||
                ex_source1_2_w ||
                ex_source1_3_w ||
                ex_source1_4_w ||
                ex_source1_5_w ||
                ex_source1_6_w ||
                ex_source1_7_w || ex_source1_wb0_w || ex_source1_wb1_w;
            assign ex_capture1_w = ({32{ex_source1_early_w}} & early_resp_data_i) |
                ({32{ex_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source1_wb0_w}} & wb0_data_i) |
                ({32{ex_source1_wb1_w}} & wb1_data_i);
            wire ex_hit2_w;
            wire [31:0] ex_capture2_w;
            wire ex_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source2_tag_r);
            wire ex_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source2_tag_r);
            assign ex_hit2_w = ex_source2_early_w || ex_source2_0_w ||
                ex_source2_1_w ||
                ex_source2_2_w ||
                ex_source2_3_w ||
                ex_source2_4_w ||
                ex_source2_5_w ||
                ex_source2_6_w ||
                ex_source2_7_w || ex_source2_wb0_w || ex_source2_wb1_w;
            assign ex_capture2_w = ({32{ex_source2_early_w}} & early_resp_data_i) |
                ({32{ex_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source2_wb0_w}} & wb0_data_i) |
                ({32{ex_source2_wb1_w}} & wb1_data_i);
            wire mem_hit1_w;
            wire [31:0] mem_capture1_w;
            wire mem_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source1_tag_r);
            wire mem_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source1_tag_r);
            assign mem_hit1_w = mem_source1_early_w || mem_source1_0_w ||
                mem_source1_1_w ||
                mem_source1_2_w ||
                mem_source1_3_w ||
                mem_source1_4_w ||
                mem_source1_5_w ||
                mem_source1_6_w ||
                mem_source1_7_w || mem_source1_wb0_w || mem_source1_wb1_w;
            assign mem_capture1_w = ({32{mem_source1_early_w}} & early_resp_data_i) |
                ({32{mem_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source1_wb0_w}} & wb0_data_i) |
                ({32{mem_source1_wb1_w}} & wb1_data_i);
            wire mem_hit2_w;
            wire [31:0] mem_capture2_w;
            wire mem_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source2_tag_r);
            wire mem_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source2_tag_r);
            assign mem_hit2_w = mem_source2_early_w || mem_source2_0_w ||
                mem_source2_1_w ||
                mem_source2_2_w ||
                mem_source2_3_w ||
                mem_source2_4_w ||
                mem_source2_5_w ||
                mem_source2_6_w ||
                mem_source2_7_w || mem_source2_wb0_w || mem_source2_wb1_w;
            assign mem_capture2_w = ({32{mem_source2_early_w}} & early_resp_data_i) |
                ({32{mem_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source2_wb0_w}} & wb0_data_i) |
                ({32{mem_source2_wb1_w}} & wb1_data_i);
            wire [31:0] ex_b_w = (ex_instr_r[6:0] == 7'h13) ?
                ex_imm_r : ex_src2_r;
            wire [31:0] ex_arithmetic_right_w = $signed(ex_src1_r) >>> ex_b_w[4:0];
            reg [31:0] ex_a_w;
            reg [31:0] ex_result_w;
            always @(*) begin
                ex_a_w = ex_src1_r;
                ex_result_w = 32'd0;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_a_w = ex_pc_r;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10)) begin
                    case (ex_instr_r[14:12])
                        3'd2: ex_a_w = ex_src1_r << 1;
                        3'd4: ex_a_w = ex_src1_r << 2;
                        3'd6: ex_a_w = ex_src1_r << 3;
                        default: ex_a_w = ex_src1_r;
                    endcase
                end
                case (ex_instr_r[14:12])
                    3'd0: ex_result_w = ex_a_w + ex_b_w;
                    3'd1: ex_result_w = ex_a_w << ex_b_w[4:0];
                    3'd2: ex_result_w = {31'd0, $signed(ex_a_w) < $signed(ex_b_w)};
                    3'd3: ex_result_w = {31'd0, ex_a_w < ex_b_w};
                    3'd4: ex_result_w = ex_a_w ^ ex_b_w;
                    3'd5: ex_result_w = ex_instr_r[30] ?
                        ex_arithmetic_right_w :
                        (ex_a_w >> ex_b_w[4:0]);
                    3'd6: ex_result_w = ex_a_w | ex_b_w;
                    3'd7: ex_result_w = ex_a_w & ex_b_w;
                    default: ex_result_w = 32'd0;
                endcase
                begin
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h20) && (ex_instr_r[14:12] == 3'd0))
                    ex_result_w = ex_a_w - ex_b_w;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10))
                    ex_result_w = ex_a_w + ex_b_w;
                if (ex_instr_r[6:0] == 7'h37)
                    ex_result_w = ex_imm_r;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_result_w = ex_a_w + ex_imm_r;
                end
            end
            wire [31:0] mem_b_w = (mem_instr_r[6:0] == 7'h13) ?
                mem_imm_r : mem_src2_r;
            reg [31:0] mem_a_w;
            reg [31:0] mem_result_w;
            always @(*) begin
                mem_a_w = mem_src1_r;
                mem_result_w = 32'd0;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10)) begin
                    case (mem_instr_r[14:12])
                        3'd2: mem_a_w = mem_src1_r << 1;
                        3'd4: mem_a_w = mem_src1_r << 2;
                        3'd6: mem_a_w = mem_src1_r << 3;
                        default: mem_a_w = mem_src1_r;
                    endcase
                end
                case (mem_instr_r[14:12])
                    3'd0: mem_result_w = mem_a_w + mem_b_w;
                    3'd2: mem_result_w = {31'd0, $signed(mem_a_w) < $signed(mem_b_w)};
                    3'd3: mem_result_w = {31'd0, mem_a_w < mem_b_w};
                    3'd4: mem_result_w = mem_a_w ^ mem_b_w;
                    3'd6: mem_result_w = mem_a_w | mem_b_w;
                    3'd7: mem_result_w = mem_a_w & mem_b_w;
                    default: mem_result_w = 32'd0;
                endcase
                begin
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h20) && (mem_instr_r[14:12] == 3'd0))
                    mem_result_w = mem_a_w - mem_b_w;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10))
                    mem_result_w = mem_a_w + mem_b_w;
                end
            end
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_instr_w = ^mem_instr_r;
            /* verilator lint_on UNUSEDSIGNAL */
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    skid_valid_r <= 1'b0;
                    mem_valid_r <= 1'b0;
                    mem_wait1_r <= 1'b0;
                    mem_wait2_r <= 1'b0;
                end else begin
                    if (skid_done_w || skid_cancel_w)
                        skid_valid_r <= 1'b0;
                    if (stash_w && !ex_cancel_w)
                        skid_valid_r <= 1'b1;
                    if (mem_done_w || mem_cancel_w)
                        mem_valid_r <= 1'b0;
                    if (mem_hit1_w)
                        mem_wait1_r <= 1'b0;
                    if (mem_hit2_w)
                        mem_wait2_r <= 1'b0;
                    if (transfer_w && !ex_cancel_w) begin
                        mem_valid_r <= 1'b1;
                        mem_wait1_r <= ex_wait1_r && !ex_hit1_w;
                        mem_wait2_r <= ex_wait2_r && !ex_hit2_w;
                    end
                end
            end
            always @(posedge clk_i) begin
                if (stash_w) begin
                    skid_tag_r <= ex_tag_r;
                    skid_data_r <= ex_result_w;
                end
                if (transfer_w) begin
                    mem_tag_r <= ex_tag_r;
                    mem_instr_r <= ex_instr_r;
                    mem_imm_r <= ex_imm_r;
                    mem_source1_tag_r <= ex_source1_tag_r;
                    mem_source2_tag_r <= ex_source2_tag_r;
                    mem_src1_r <= (ex_wait1_r && ex_hit1_w) ?
                        ex_capture1_w : ex_src1_r;
                    mem_src2_r <= (ex_wait2_r && ex_hit2_w) ?
                        ex_capture2_w : ex_src2_r;
                end else begin
                    if (mem_wait1_r && mem_hit1_w)
                        mem_src1_r <= mem_capture1_w;
                    if (mem_wait2_r && mem_hit2_w)
                        mem_src2_r <= mem_capture2_w;
                end
            end
            assign compare0_valid_w = select_skid_w || select_mem_w || select_ex_w;
            assign compare0_tag_w = select_skid_w ? skid_tag_r :
                select_mem_w ? mem_tag_r : ex_tag_r;
            assign compare0_data_w = {{(B-32){1'b0}},
                select_skid_w ? skid_data_r : select_mem_w ? mem_result_w : ex_result_w};
            assign compare0_flags_w = 5'd0;
            assign compare0_exception_w = 1'd0;
            assign compare0_cause_w = 4'd0;
            assign compare0_tval_w = 32'd0;
        end else begin : g_inactive0
            assign compare0_valid_w = 1'd0;
            assign compare0_tag_w = {T{1'b0}};
            assign compare0_data_w = {B{1'b0}};
            assign compare0_flags_w = 5'd0;
            assign compare0_exception_w = 1'd0;
            assign compare0_cause_w = 4'd0;
            assign compare0_tval_w = 32'd0;
            assign execute0_ready_o = 1'b0;
            assign debug_mem_valid_o[0] = 1'b0;
        end
    endgenerate
    generate
        if (ISSUE_WIDTH > 1) begin : g_pipe1
            reg skid_valid_r;
            reg [T-1:0] skid_tag_r;
            reg [31:0] skid_data_r;
            reg mem_valid_r;
            assign debug_mem_valid_o[1] = mem_valid_r;
            reg [T-1:0] mem_tag_r;
            reg [31:0] mem_instr_r;
            reg [31:0] mem_src1_r;
            reg [31:0] mem_src2_r;
            reg [31:0] mem_imm_r;
            reg [T-1:0] mem_source1_tag_r;
            reg [T-1:0] mem_source2_tag_r;
            reg mem_wait1_r;
            reg mem_wait2_r;
            wire ex_valid_r = execute1_valid_i && execute1_ready_o && !input_cancel_w;
            wire ex_late_r = (ISSUE_WIDTH == 2) && execute1_late_i;
            wire [T-1:0] ex_tag_r = execute1_tag_i;
            wire [32-1:0] ex_pc_r = execute1_pc_i;
            wire [32-1:0] ex_instr_r = compare1_instr_w;
            wire [32-1:0] ex_src1_r = (execute1_instr_i[6:0] == 7'h63) ?
                        execute1_src1_i : 32'd0;
            wire [32-1:0] ex_src2_r = (execute1_instr_i[6:0] == 7'h63) ?
                        execute1_src2_i : 32'd0;
            wire [32-1:0] ex_imm_r = execute1_imm_i;
            wire [T-1:0] ex_source1_tag_r = execute1_source1_tag_i;
            wire [T-1:0] ex_source2_tag_r = execute1_source2_tag_i;
            wire ex_wait1_r = (ISSUE_WIDTH == 2) && execute1_source1_wait_i;
            wire ex_wait2_r = (ISSUE_WIDTH == 2) && execute1_source2_wait_i;
            wire [T-1:0] ex_age_w = ex_tag_r - age_head_i;
            wire ex_cancel_w = cancel_valid_i && (ex_age_w >= cancel_age_w);
            wire [T-1:0] skid_age_w = skid_tag_r - age_head_i;
            wire skid_cancel_w = skid_valid_r && cancel_valid_i && (skid_age_w >= cancel_age_w);
            wire [T-1:0] mem_age_w = mem_tag_r - age_head_i;
            wire mem_cancel_w = mem_valid_r && cancel_valid_i && (mem_age_w >= cancel_age_w);
            wire [T-1:0] input_age_w = execute1_tag_i - age_head_i;
            wire input_cancel_w = execute1_valid_i && cancel_valid_i &&
                (input_age_w >= cancel_age_w);
            wire [T-1:0] cancel_age_w = cancel_tag_i - age_head_i;
            wire ex_early_w = ex_valid_r && !ex_late_r;
            wire mem_ready_w = mem_valid_r && !mem_wait1_r && !mem_wait2_r;
            assign execute1_ready_o = ex_late_r ? !mem_valid_r : !skid_valid_r;
            wire transfer_w = ex_valid_r && ex_late_r && !mem_valid_r;
            reg lock_valid_r;
            reg [T-1:0] lock_tag_r;
            wire candidate_skid_w = skid_valid_r &&
                (!mem_ready_w || (skid_age_w < mem_age_w));
            wire candidate_mem_w = mem_ready_w && !candidate_skid_w &&
                (!ex_early_w || (mem_age_w < ex_age_w));
            wire candidate_ex_w = ex_early_w && !candidate_skid_w && !candidate_mem_w;
            wire select_skid_w = lock_valid_r ?
                (skid_valid_r && (skid_tag_r == lock_tag_r)) : candidate_skid_w;
            wire select_mem_w = lock_valid_r ?
                (mem_ready_w && (mem_tag_r == lock_tag_r)) : candidate_mem_w;
            wire select_ex_w = lock_valid_r ?
                (ex_early_w && (ex_tag_r == lock_tag_r)) : candidate_ex_w;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    lock_valid_r <= 1'b0;
                else if (compare1_valid_w && compare1_ready_w)
                    lock_valid_r <= 1'b0;
                else if (lock_valid_r && cancel_valid_i &&
                    ((lock_tag_r-age_head_i) >= cancel_age_w))
                    lock_valid_r <= 1'b0;
                else if (compare1_valid_w &&
                    !(cancel_valid_i && compare1_age_w >= cancel_age_w))
                    lock_valid_r <= 1'b1;
            end
            always @(posedge clk_i) begin
                if (compare1_valid_w && !compare1_ready_w)
                    lock_tag_r <= compare1_tag_w;
            end
            wire ex_done_w = select_ex_w && compare1_ready_w;
            wire skid_done_w = select_skid_w && compare1_ready_w;
            wire mem_done_w = select_mem_w && compare1_ready_w;
            wire stash_w = ex_early_w && !skid_valid_r && !ex_done_w;
            wire ex_hit1_w;
            wire [31:0] ex_capture1_w;
            wire ex_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source1_tag_r);
            wire ex_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source1_tag_r);
            assign ex_hit1_w = ex_source1_early_w || ex_source1_0_w ||
                ex_source1_1_w ||
                ex_source1_2_w ||
                ex_source1_3_w ||
                ex_source1_4_w ||
                ex_source1_5_w ||
                ex_source1_6_w ||
                ex_source1_7_w || ex_source1_wb0_w || ex_source1_wb1_w;
            assign ex_capture1_w = ({32{ex_source1_early_w}} & early_resp_data_i) |
                ({32{ex_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source1_wb0_w}} & wb0_data_i) |
                ({32{ex_source1_wb1_w}} & wb1_data_i);
            wire ex_hit2_w;
            wire [31:0] ex_capture2_w;
            wire ex_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source2_tag_r);
            wire ex_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source2_tag_r);
            assign ex_hit2_w = ex_source2_early_w || ex_source2_0_w ||
                ex_source2_1_w ||
                ex_source2_2_w ||
                ex_source2_3_w ||
                ex_source2_4_w ||
                ex_source2_5_w ||
                ex_source2_6_w ||
                ex_source2_7_w || ex_source2_wb0_w || ex_source2_wb1_w;
            assign ex_capture2_w = ({32{ex_source2_early_w}} & early_resp_data_i) |
                ({32{ex_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source2_wb0_w}} & wb0_data_i) |
                ({32{ex_source2_wb1_w}} & wb1_data_i);
            wire mem_hit1_w;
            wire [31:0] mem_capture1_w;
            wire mem_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source1_tag_r);
            wire mem_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source1_tag_r);
            assign mem_hit1_w = mem_source1_early_w || mem_source1_0_w ||
                mem_source1_1_w ||
                mem_source1_2_w ||
                mem_source1_3_w ||
                mem_source1_4_w ||
                mem_source1_5_w ||
                mem_source1_6_w ||
                mem_source1_7_w || mem_source1_wb0_w || mem_source1_wb1_w;
            assign mem_capture1_w = ({32{mem_source1_early_w}} & early_resp_data_i) |
                ({32{mem_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source1_wb0_w}} & wb0_data_i) |
                ({32{mem_source1_wb1_w}} & wb1_data_i);
            wire mem_hit2_w;
            wire [31:0] mem_capture2_w;
            wire mem_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source2_tag_r);
            wire mem_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source2_tag_r);
            assign mem_hit2_w = mem_source2_early_w || mem_source2_0_w ||
                mem_source2_1_w ||
                mem_source2_2_w ||
                mem_source2_3_w ||
                mem_source2_4_w ||
                mem_source2_5_w ||
                mem_source2_6_w ||
                mem_source2_7_w || mem_source2_wb0_w || mem_source2_wb1_w;
            assign mem_capture2_w = ({32{mem_source2_early_w}} & early_resp_data_i) |
                ({32{mem_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source2_wb0_w}} & wb0_data_i) |
                ({32{mem_source2_wb1_w}} & wb1_data_i);
            wire [31:0] ex_b_w = (ex_instr_r[6:0] == 7'h13) ?
                ex_imm_r : ex_src2_r;
            wire [31:0] ex_arithmetic_right_w = $signed(ex_src1_r) >>> ex_b_w[4:0];
            reg [31:0] ex_a_w;
            reg [31:0] ex_result_w;
            always @(*) begin
                ex_a_w = ex_src1_r;
                ex_result_w = 32'd0;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_a_w = ex_pc_r;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10)) begin
                    case (ex_instr_r[14:12])
                        3'd2: ex_a_w = ex_src1_r << 1;
                        3'd4: ex_a_w = ex_src1_r << 2;
                        3'd6: ex_a_w = ex_src1_r << 3;
                        default: ex_a_w = ex_src1_r;
                    endcase
                end
                case (ex_instr_r[14:12])
                    3'd0: ex_result_w = ex_a_w + ex_b_w;
                    3'd1: ex_result_w = ex_a_w << ex_b_w[4:0];
                    3'd2: ex_result_w = {31'd0, $signed(ex_a_w) < $signed(ex_b_w)};
                    3'd3: ex_result_w = {31'd0, ex_a_w < ex_b_w};
                    3'd4: ex_result_w = ex_a_w ^ ex_b_w;
                    3'd5: ex_result_w = ex_instr_r[30] ?
                        ex_arithmetic_right_w :
                        (ex_a_w >> ex_b_w[4:0]);
                    3'd6: ex_result_w = ex_a_w | ex_b_w;
                    3'd7: ex_result_w = ex_a_w & ex_b_w;
                    default: ex_result_w = 32'd0;
                endcase
                begin
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h20) && (ex_instr_r[14:12] == 3'd0))
                    ex_result_w = ex_a_w - ex_b_w;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10))
                    ex_result_w = ex_a_w + ex_b_w;
                if (ex_instr_r[6:0] == 7'h37)
                    ex_result_w = ex_imm_r;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_result_w = ex_a_w + ex_imm_r;
                end
            end
            wire [31:0] mem_b_w = (mem_instr_r[6:0] == 7'h13) ?
                mem_imm_r : mem_src2_r;
            reg [31:0] mem_a_w;
            reg [31:0] mem_result_w;
            always @(*) begin
                mem_a_w = mem_src1_r;
                mem_result_w = 32'd0;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10)) begin
                    case (mem_instr_r[14:12])
                        3'd2: mem_a_w = mem_src1_r << 1;
                        3'd4: mem_a_w = mem_src1_r << 2;
                        3'd6: mem_a_w = mem_src1_r << 3;
                        default: mem_a_w = mem_src1_r;
                    endcase
                end
                case (mem_instr_r[14:12])
                    3'd0: mem_result_w = mem_a_w + mem_b_w;
                    3'd2: mem_result_w = {31'd0, $signed(mem_a_w) < $signed(mem_b_w)};
                    3'd3: mem_result_w = {31'd0, mem_a_w < mem_b_w};
                    3'd4: mem_result_w = mem_a_w ^ mem_b_w;
                    3'd6: mem_result_w = mem_a_w | mem_b_w;
                    3'd7: mem_result_w = mem_a_w & mem_b_w;
                    default: mem_result_w = 32'd0;
                endcase
                begin
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h20) && (mem_instr_r[14:12] == 3'd0))
                    mem_result_w = mem_a_w - mem_b_w;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10))
                    mem_result_w = mem_a_w + mem_b_w;
                end
            end
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_instr_w = ^mem_instr_r;
            /* verilator lint_on UNUSEDSIGNAL */
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    skid_valid_r <= 1'b0;
                    mem_valid_r <= 1'b0;
                    mem_wait1_r <= 1'b0;
                    mem_wait2_r <= 1'b0;
                end else begin
                    if (skid_done_w || skid_cancel_w)
                        skid_valid_r <= 1'b0;
                    if (stash_w && !ex_cancel_w)
                        skid_valid_r <= 1'b1;
                    if (mem_done_w || mem_cancel_w)
                        mem_valid_r <= 1'b0;
                    if (mem_hit1_w)
                        mem_wait1_r <= 1'b0;
                    if (mem_hit2_w)
                        mem_wait2_r <= 1'b0;
                    if (transfer_w && !ex_cancel_w) begin
                        mem_valid_r <= 1'b1;
                        mem_wait1_r <= ex_wait1_r && !ex_hit1_w;
                        mem_wait2_r <= ex_wait2_r && !ex_hit2_w;
                    end
                end
            end
            always @(posedge clk_i) begin
                if (stash_w) begin
                    skid_tag_r <= ex_tag_r;
                    skid_data_r <= ex_result_w;
                end
                if (transfer_w) begin
                    mem_tag_r <= ex_tag_r;
                    mem_instr_r <= ex_instr_r;
                    mem_imm_r <= ex_imm_r;
                    mem_source1_tag_r <= ex_source1_tag_r;
                    mem_source2_tag_r <= ex_source2_tag_r;
                    mem_src1_r <= (ex_wait1_r && ex_hit1_w) ?
                        ex_capture1_w : ex_src1_r;
                    mem_src2_r <= (ex_wait2_r && ex_hit2_w) ?
                        ex_capture2_w : ex_src2_r;
                end else begin
                    if (mem_wait1_r && mem_hit1_w)
                        mem_src1_r <= mem_capture1_w;
                    if (mem_wait2_r && mem_hit2_w)
                        mem_src2_r <= mem_capture2_w;
                end
            end
            assign compare1_valid_w = select_skid_w || select_mem_w || select_ex_w;
            assign compare1_tag_w = select_skid_w ? skid_tag_r :
                select_mem_w ? mem_tag_r : ex_tag_r;
            assign compare1_data_w = {{(B-32){1'b0}},
                select_skid_w ? skid_data_r : select_mem_w ? mem_result_w : ex_result_w};
            assign compare1_flags_w = 5'd0;
            assign compare1_exception_w = 1'd0;
            assign compare1_cause_w = 4'd0;
            assign compare1_tval_w = 32'd0;
        end else begin : g_inactive1
            assign compare1_valid_w = 1'd0;
            assign compare1_tag_w = {T{1'b0}};
            assign compare1_data_w = {B{1'b0}};
            assign compare1_flags_w = 5'd0;
            assign compare1_exception_w = 1'd0;
            assign compare1_cause_w = 4'd0;
            assign compare1_tval_w = 32'd0;
            assign execute1_ready_o = 1'b0;
            assign debug_mem_valid_o[1] = 1'b0;
        end
    endgenerate
    wire [T-1:0] cancel_age_w = cancel_tag_i - age_head_i;
    wire live0_w = compare0_valid_w &&
        !(cancel_valid_i && (compare0_age_w >= cancel_age_w));
    wire live1_w = compare1_valid_w &&
        !(cancel_valid_i && (compare1_age_w >= cancel_age_w));
    wire ex0_w = live0_w && !meta_seen_w[compare0_tag_w] &&
        !meta_late_w[compare0_tag_w];
    wire ex1_w = live1_w && !meta_seen_w[compare1_tag_w] &&
        !meta_late_w[compare1_tag_w];
    wire ex_choose1_w = ex1_w && (!ex0_w || (compare1_age_w < compare0_age_w));
    wire ex_resolve_w = ex0_w || ex1_w;
    wire [T-1:0] ex_tag_w = ex_choose1_w ? compare1_tag_w : compare0_tag_w;
    wire [31:0] ex_compare_w = ex_choose1_w ? compare1_data_w[31:0] :
        compare0_data_w[31:0];
    wire [31:0] ex_pc_w = meta_pc_w[ex_tag_w];
    wire [31:0] ex_instr_w = meta_instr_w[ex_tag_w];
    wire [31:0] ex_imm_w = meta_imm_w[ex_tag_w];
    wire ex_conditional_w = ex_instr_w[6:0] == 7'h63;
    wire ex_jalr_w = ex_instr_w[6:0] == 7'h67;
    wire ex_taken_w = !ex_conditional_w ||
        ((ex_instr_w[14:13] == 2'd0 ? (ex_compare_w == 32'd0) :
        ex_compare_w[0]) ^ ex_instr_w[12]);
    wire [31:0] ex_sum_w = (ex_jalr_w ? meta_src1_w[ex_tag_w] : ex_pc_w) + ex_imm_w;
    wire [31:0] ex_target_w = ex_sum_w & (ex_jalr_w ? 32'hffff_fffe : 32'hffff_ffff);
    wire [31:0] ex_link_w = ex_pc_w + 32'd4;
    wire [31:0] ex_next_w = ex_taken_w ? ex_target_w : ex_link_w;
    wire ex_exception_w = ex_taken_w && (|ex_target_w[1:0]);
    wire ex_mispredict_w = ex_resolve_w && !ex_exception_w &&
        ((meta_predict_taken_w[ex_tag_w] != ex_taken_w) ||
        (ex_taken_w && (meta_predict_target_w[ex_tag_w] != ex_target_w)));
    wire ex_rd_link_w = (ex_instr_w[11:7] == 5'd1) || (ex_instr_w[11:7] == 5'd5);
    wire ex_rs_link_w = (ex_instr_w[19:15] == 5'd1) || (ex_instr_w[19:15] == 5'd5);
    wire ex_push_w = !ex_conditional_w && ex_rd_link_w;
    wire ex_pop_w = ex_jalr_w && ex_rs_link_w &&
        (!ex_rd_link_w || (ex_instr_w[19:15] != ex_instr_w[11:7]));
    wire [2:0] ex_type_w = ex_conditional_w ? 3'd0 :
        (ex_pop_w && ex_push_w) ? 3'd5 : ex_pop_w ? 3'd4 :
        ex_push_w ? 3'd3 : ex_jalr_w ? 3'd2 : 3'd1;
    wire mem0_w = live0_w && !meta_seen_w[compare0_tag_w] &&
        meta_late_w[compare0_tag_w];
    wire mem1_w = live1_w && !meta_seen_w[compare1_tag_w] &&
        meta_late_w[compare1_tag_w];
    wire mem_choose1_w = mem1_w && (!mem0_w || (compare1_age_w < compare0_age_w));
    wire mem_resolve_w = mem0_w || mem1_w;
    wire [T-1:0] mem_tag_w = mem_choose1_w ? compare1_tag_w : compare0_tag_w;
    wire [31:0] mem_compare_w = mem_choose1_w ? compare1_data_w[31:0] :
        compare0_data_w[31:0];
    wire [31:0] mem_pc_w = meta_pc_w[mem_tag_w];
    wire [31:0] mem_instr_w = meta_instr_w[mem_tag_w];
    wire [31:0] mem_imm_w = meta_imm_w[mem_tag_w];
    wire mem_conditional_w = mem_instr_w[6:0] == 7'h63;
    wire mem_jalr_w = mem_instr_w[6:0] == 7'h67;
    wire mem_taken_w = !mem_conditional_w ||
        ((mem_instr_w[14:13] == 2'd0 ? (mem_compare_w == 32'd0) :
        mem_compare_w[0]) ^ mem_instr_w[12]);
    wire [31:0] mem_sum_w = mem_pc_w + mem_imm_w;
    wire [31:0] mem_target_w = mem_sum_w & (mem_jalr_w ? 32'hffff_fffe : 32'hffff_ffff);
    wire [31:0] mem_link_w = mem_pc_w + 32'd4;
    wire [31:0] mem_next_w = mem_taken_w ? mem_target_w : mem_link_w;
    wire mem_exception_w = mem_taken_w && (|mem_target_w[1:0]);
    wire mem_mispredict_w = mem_resolve_w && !mem_exception_w &&
        ((meta_predict_taken_w[mem_tag_w] != mem_taken_w) ||
        (mem_taken_w && (meta_predict_target_w[mem_tag_w] != mem_target_w)));
    wire mem_rd_link_w = (mem_instr_w[11:7] == 5'd1) || (mem_instr_w[11:7] == 5'd5);
    wire mem_rs_link_w = (mem_instr_w[19:15] == 5'd1) || (mem_instr_w[19:15] == 5'd5);
    wire mem_push_w = !mem_conditional_w && mem_rd_link_w;
    wire mem_pop_w = mem_jalr_w && mem_rs_link_w &&
        (!mem_rd_link_w || (mem_instr_w[19:15] != mem_instr_w[11:7]));
    wire [2:0] mem_type_w = mem_conditional_w ? 3'd0 :
        (mem_pop_w && mem_push_w) ? 3'd5 : mem_pop_w ? 3'd4 :
        mem_push_w ? 3'd3 : mem_jalr_w ? 3'd2 : 3'd1;
    reg lock_valid_r;
    reg [T-1:0] lock_tag_r;
    wire choose1_w = lock_valid_r ?
        (compare1_valid_w && compare1_tag_w == lock_tag_r) :
        (compare1_valid_w && (!compare0_valid_w || (compare1_age_w < compare0_age_w)));
    wire [T-1:0] result_tag_w = choose1_w ? compare1_tag_w : compare0_tag_w;
    wire result_valid_w = choose1_w ? compare1_valid_w : compare0_valid_w;
    wire result_resolved_w = meta_seen_w[result_tag_w] ||
        (ex_resolve_w && (ex_tag_w == result_tag_w)) ||
        (mem_resolve_w && (mem_tag_w == result_tag_w));
    wire [31:0] result_target_w = meta_seen_w[result_tag_w] ?
        meta_resolved_target_w[result_tag_w] :
        (ex_resolve_w && (ex_tag_w == result_tag_w)) ? ex_target_w : mem_target_w;
    wire [31:0] result_next_w = meta_seen_w[result_tag_w] ?
        meta_resolved_next_w[result_tag_w] :
        (ex_resolve_w && (ex_tag_w == result_tag_w)) ? ex_next_w : mem_next_w;
    wire [31:0] result_link_w = meta_seen_w[result_tag_w] ?
        meta_resolved_link_w[result_tag_w] :
        (ex_resolve_w && (ex_tag_w == result_tag_w)) ? ex_link_w : mem_link_w;
    wire result_exception_w = meta_seen_w[result_tag_w] ?
        meta_resolved_exception_w[result_tag_w] :
        (ex_resolve_w && (ex_tag_w == result_tag_w)) ? ex_exception_w : mem_exception_w;
    assign branch_complete_valid_o = result_valid_w && result_resolved_w;
    assign branch_complete_tag_o = result_tag_w;
    assign branch_complete_data_o = {{(B-32){1'b0}}, result_link_w};
    assign branch_complete_next_pc_o = result_next_w;
    assign branch_complete_flags_o = 5'd0;
    assign branch_complete_exception_o = result_exception_w;
    assign branch_complete_cause_o = 4'd0;
    assign branch_complete_tval_o = result_target_w;
    assign compare0_ready_w = branch_complete_ready_i && !choose1_w && result_resolved_w;
    assign compare1_ready_w = branch_complete_ready_i && choose1_w && result_resolved_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            lock_valid_r <= 1'b0;
        else if (lock_valid_r && cancel_valid_i &&
                    ((lock_tag_r-age_head_i) >= cancel_age_w))
            lock_valid_r <= 1'b0;
        else if (branch_complete_valid_o && branch_complete_ready_i)
            lock_valid_r <= 1'b0;
        else if (branch_complete_valid_o &&
            !(cancel_valid_i && (branch_complete_tag_o-age_head_i) >= cancel_age_w))
            lock_valid_r <= 1'b1;
    end
    always @(posedge clk_i) begin
        if (branch_complete_valid_o && !branch_complete_ready_i)
            lock_tag_r <= branch_complete_tag_o;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ex_predict_train_valid_o <= 1'b0;
            mem_predict_train_valid_r <= 1'b0;
            branch_redirect_valid_o <= 1'b0;
        end else begin
            // Faulting control flow does not train BTB, fast direction or TAGE.
            ex_predict_train_valid_o <= ex_resolve_w && !ex_exception_w;
            mem_predict_train_valid_r <= (ISSUE_WIDTH == 2) &&
                mem_resolve_w && !mem_exception_w;
            branch_redirect_valid_o <= ex_mispredict_w || mem_mispredict_w;
        end
    end
    wire redirect_mem_w = mem_mispredict_w && (!ex_mispredict_w ||
        ((mem_tag_w-age_head_i) < (ex_tag_w-age_head_i)));
    wire [T-1:0] redirect_tag_w = redirect_mem_w ? mem_tag_w : ex_tag_w;
    always @(posedge clk_i) begin
        if (ex_resolve_w) begin
            ex_predict_train_tag_o <= ex_tag_w;
            ex_predict_train_pc_o <= ex_pc_w;
            ex_predict_train_taken_o <= ex_taken_w;
            ex_predict_train_target_o <= ex_target_w;
            ex_predict_train_type_o <= ex_type_w;
            ex_predict_train_token_r <= (ISSUE_WIDTH == 2) ? meta_predict_token_w[ex_tag_w] : 1'b0;
            ex_predict_train_provider_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_provider_w[ex_tag_w] : 3'd0;
            ex_predict_train_alternate_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_alternate_w[ex_tag_w] : 1'b0;
            ex_predict_train_prediction_r <= meta_predict_taken_w[ex_tag_w];
            ex_predict_train_index0_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index0_w[ex_tag_w] : 9'd0;
            ex_predict_train_index1_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index1_w[ex_tag_w] : 9'd0;
            ex_predict_train_index2_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index2_w[ex_tag_w] : 9'd0;
            ex_predict_train_index3_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index3_w[ex_tag_w] : 9'd0;
            ex_predict_train_tag0_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag0_w[ex_tag_w] : 10'd0;
            ex_predict_train_tag1_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag1_w[ex_tag_w] : 10'd0;
            ex_predict_train_tag2_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag2_w[ex_tag_w] : 10'd0;
            ex_predict_train_tag3_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag3_w[ex_tag_w] : 10'd0;
            ex_predict_train_base_index_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_base_index_w[ex_tag_w] : 12'd0;
            ex_predict_train_fast_index_o <= meta_predict_fast_index_w[ex_tag_w];
        end
        if (mem_resolve_w) begin
            mem_predict_train_tag_r <= mem_tag_w;
            mem_predict_train_pc_r <= mem_pc_w;
            mem_predict_train_taken_r <= mem_taken_w;
            mem_predict_train_target_r <= mem_target_w;
            mem_predict_train_type_r <= mem_type_w;
            mem_predict_train_token_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_token_w[mem_tag_w] : 1'b0;
            mem_predict_train_provider_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_provider_w[mem_tag_w] : 3'd0;
            mem_predict_train_alternate_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_alternate_w[mem_tag_w] : 1'b0;
            mem_predict_train_prediction_r <= meta_predict_taken_w[mem_tag_w];
            mem_predict_train_index0_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index0_w[mem_tag_w] : 9'd0;
            mem_predict_train_index1_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index1_w[mem_tag_w] : 9'd0;
            mem_predict_train_index2_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index2_w[mem_tag_w] : 9'd0;
            mem_predict_train_index3_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_index3_w[mem_tag_w] : 9'd0;
            mem_predict_train_tag0_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag0_w[mem_tag_w] : 10'd0;
            mem_predict_train_tag1_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag1_w[mem_tag_w] : 10'd0;
            mem_predict_train_tag2_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag2_w[mem_tag_w] : 10'd0;
            mem_predict_train_tag3_r <= (ISSUE_WIDTH == 2) ? meta_predict_tag3_w[mem_tag_w] : 10'd0;
            mem_predict_train_base_index_r <=
                (ISSUE_WIDTH == 2) ? meta_predict_base_index_w[mem_tag_w] : 12'd0;
            mem_predict_train_fast_index_r <= meta_predict_fast_index_w[mem_tag_w];
        end
        if (ex_mispredict_w || mem_mispredict_w) begin
            trace_branch_pc_o <= redirect_mem_w ? mem_pc_w : ex_pc_w;
            trace_branch_stage_o <= redirect_mem_w ? 2'd3 : 2'd2;
            trace_branch_cause_o <= redirect_mem_w ?
                (meta_predict_taken_w[mem_tag_w] != mem_taken_w ? 2'd1 : 2'd2) :
                (meta_predict_taken_w[ex_tag_w] != ex_taken_w ? 2'd1 : 2'd2);
            branch_redirect_tag_o <= redirect_tag_w;
            branch_redirect_pc_o <= redirect_mem_w ? mem_next_w : ex_next_w;
            branch_redirect_ras_data_o <= meta_ras_data_w[redirect_tag_w];
            branch_redirect_ras_ptr_o <= meta_ras_ptr_w[redirect_tag_w];
            branch_redirect_ras_count_o <= meta_ras_count_w[redirect_tag_w];
            branch_redirect_ras_pop_o <= redirect_mem_w ? mem_pop_w : ex_pop_w;
            branch_redirect_ras_push_o <= redirect_mem_w ? mem_push_w : ex_push_w;
            branch_redirect_link_o <= redirect_mem_w ? mem_link_w : ex_link_w;
        end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{early_resp_valid_i, early_resp_tag_i, early_resp_hit_i,
        early_resp_data_i, lsu_complete_device_i,
        wb0_valid_i,
        wb0_tag_i,
        wb0_data_i,
        wb1_valid_i,
        wb1_tag_i,
        wb1_data_i,
        clk_i,
        rst_n_i,
        age_head_i,
        cancel_valid_i,
        cancel_tag_i,
        execute0_valid_i,
        execute0_tag_i,
        execute0_pc_i,
        execute0_instr_i,
        execute0_src1_i,
        execute0_src2_i,
        execute0_imm_i,
        execute0_late_i,
        execute0_source1_tag_i,
        execute0_source2_tag_i,
        execute0_source1_wait_i,
        execute0_source2_wait_i,
        execute0_predict_taken_i,
        execute0_predict_target_i,
        execute0_predict_token_i,
        execute0_predict_provider_i,
        execute0_predict_alternate_i,
        execute0_predict_index0_i,
        execute0_predict_index1_i,
        execute0_predict_index2_i,
        execute0_predict_index3_i,
        execute0_predict_tag0_i,
        execute0_predict_tag1_i,
        execute0_predict_tag2_i,
        execute0_predict_tag3_i,
        execute0_predict_base_index_i,
        execute0_predict_fast_index_i,
        execute0_ras_data_i,
        execute0_ras_ptr_i,
        execute0_ras_count_i,
        execute1_valid_i,
        execute1_tag_i,
        execute1_pc_i,
        execute1_instr_i,
        execute1_src1_i,
        execute1_src2_i,
        execute1_imm_i,
        execute1_late_i,
        execute1_source1_tag_i,
        execute1_source2_tag_i,
        execute1_source1_wait_i,
        execute1_source2_wait_i,
        execute1_predict_taken_i,
        execute1_predict_target_i,
        execute1_predict_token_i,
        execute1_predict_provider_i,
        execute1_predict_alternate_i,
        execute1_predict_index0_i,
        execute1_predict_index1_i,
        execute1_predict_index2_i,
        execute1_predict_index3_i,
        execute1_predict_tag0_i,
        execute1_predict_tag1_i,
        execute1_predict_tag2_i,
        execute1_predict_tag3_i,
        execute1_predict_base_index_i,
        execute1_predict_fast_index_i,
        execute1_ras_data_i,
        execute1_ras_ptr_i,
        execute1_ras_count_i,
        alu0_complete_valid_i,
        alu0_complete_ready_i,
        alu0_complete_tag_i,
        alu0_complete_data_i,
        alu1_complete_valid_i,
        alu1_complete_ready_i,
        alu1_complete_tag_i,
        alu1_complete_data_i,
        branch_complete_valid_i,
        branch_complete_ready_i,
        branch_complete_tag_i,
        branch_complete_data_i,
        mul_complete_valid_i,
        mul_complete_ready_i,
        mul_complete_tag_i,
        mul_complete_data_i,
        div_complete_valid_i,
        div_complete_ready_i,
        div_complete_tag_i,
        div_complete_data_i,
        lsu_complete_valid_i,
        lsu_complete_ready_i,
        lsu_complete_tag_i,
        lsu_complete_data_i,
        csr_complete_valid_i,
        csr_complete_ready_i,
        csr_complete_tag_i,
        csr_complete_data_i,
        fp_resp_valid_i,
        fp_resp_ready_i,
        fp_resp_tag_i,
        fp_resp_data_i,
        compare0_data_w,
        compare1_data_w,
        compare0_instr_w,
        compare1_instr_w,
        compare0_ready_w,
        compare1_ready_w,
        condition0_w,
        condition1_w,
        ex_instr_w,
        mem_instr_w,
        ex_predict_train_token_r,
        ex_predict_train_provider_r,
        ex_predict_train_alternate_r,
        ex_predict_train_prediction_r,
        ex_predict_train_index0_r,
        ex_predict_train_index1_r,
        ex_predict_train_index2_r,
        ex_predict_train_index3_r,
        ex_predict_train_tag0_r,
        ex_predict_train_tag1_r,
        ex_predict_train_tag2_r,
        ex_predict_train_tag3_r,
        ex_predict_train_base_index_r,
        mem_predict_train_valid_r,
        mem_predict_train_tag_r,
        mem_predict_train_pc_r,
        mem_predict_train_taken_r,
        mem_predict_train_target_r,
        mem_predict_train_type_r,
        mem_predict_train_token_r,
        mem_predict_train_provider_r,
        mem_predict_train_alternate_r,
        mem_predict_train_prediction_r,
        mem_predict_train_index0_r,
        mem_predict_train_index1_r,
        mem_predict_train_index2_r,
        mem_predict_train_index3_r,
        mem_predict_train_tag0_r,
        mem_predict_train_tag1_r,
        mem_predict_train_tag2_r,
        mem_predict_train_tag3_r,
        mem_predict_train_base_index_r,
        mem_predict_train_fast_index_r,
        compare0_flags_w,
        compare0_exception_w,
        compare0_cause_w,
        compare0_tval_w,
        compare1_flags_w,
        compare1_exception_w,
        compare1_cause_w,
        compare1_tval_w};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
