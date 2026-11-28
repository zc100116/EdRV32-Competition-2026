// CV02/CV04/CV05 independent program-slot/type/age oracle and execution stubs.
module tb #(parameter ISSUE_WIDTH=2,parameter [31:0] FPU_FORMAT="NONE");
    localparam T=ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam N=2**T;
    localparam B=FPU_FORMAT=="FD"?64:32;
    reg clk_i=0;
    reg rst_n_i=0;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i;
    reg cancel_valid_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i=0;
    reg [2-1:0] csr_fs_i=0;
    reg [3-1:0] csr_frm_i=0;
    reg ib_head0_valid_i=0;
    reg [32-1:0] ib_head0_pc_i=0;
    reg [32-1:0] ib_head0_instr_i=0;
    reg ib_head0_error_i=0;
    reg [5-1:0] ib_head0_candidates_i=0;
    reg ib_head0_predict_taken_i=0;
    reg [32-1:0] ib_head0_predict_target_i=0;
    reg ib_head0_predict_token_i=0;
    reg [3-1:0] ib_head0_predict_provider_i=0;
    reg ib_head0_predict_alternate_i=0;
    reg [9-1:0] ib_head0_predict_index0_i=0;
    reg [9-1:0] ib_head0_predict_index1_i=0;
    reg [9-1:0] ib_head0_predict_index2_i=0;
    reg [9-1:0] ib_head0_predict_index3_i=0;
    reg [10-1:0] ib_head0_predict_tag0_i=0;
    reg [10-1:0] ib_head0_predict_tag1_i=0;
    reg [10-1:0] ib_head0_predict_tag2_i=0;
    reg [10-1:0] ib_head0_predict_tag3_i=0;
    reg [12-1:0] ib_head0_predict_base_index_i=0;
    reg [12-1:0] ib_head0_predict_fast_index_i=0;
    reg [(128*ISSUE_WIDTH)-1:0] ib_head0_ras_data_i=0;
    reg [(ISSUE_WIDTH+1)-1:0] ib_head0_ras_ptr_i=0;
    reg [(ISSUE_WIDTH+2)-1:0] ib_head0_ras_count_i=0;
    reg ib_head1_valid_i=0;
    reg [32-1:0] ib_head1_pc_i=0;
    reg [32-1:0] ib_head1_instr_i=0;
    reg ib_head1_error_i=0;
    reg [5-1:0] ib_head1_candidates_i=0;
    reg ib_head1_predict_taken_i=0;
    reg [32-1:0] ib_head1_predict_target_i=0;
    reg ib_head1_predict_token_i=0;
    reg [3-1:0] ib_head1_predict_provider_i=0;
    reg ib_head1_predict_alternate_i=0;
    reg [9-1:0] ib_head1_predict_index0_i=0;
    reg [9-1:0] ib_head1_predict_index1_i=0;
    reg [9-1:0] ib_head1_predict_index2_i=0;
    reg [9-1:0] ib_head1_predict_index3_i=0;
    reg [10-1:0] ib_head1_predict_tag0_i=0;
    reg [10-1:0] ib_head1_predict_tag1_i=0;
    reg [10-1:0] ib_head1_predict_tag2_i=0;
    reg [10-1:0] ib_head1_predict_tag3_i=0;
    reg [12-1:0] ib_head1_predict_base_index_i=0;
    reg [12-1:0] ib_head1_predict_fast_index_i=0;
    reg [(128*ISSUE_WIDTH)-1:0] ib_head1_ras_data_i=0;
    reg [(ISSUE_WIDTH+1)-1:0] ib_head1_ras_ptr_i=0;
    reg [(ISSUE_WIDTH+2)-1:0] ib_head1_ras_count_i=0;
    wire [2-1:0] ib_remove_count_o;
    wire [5-1:0] id_rs0_o;
    wire id_owner0_o;
    wire [32-1:0] id_data0_i;
    wire [5-1:0] id_rs1_o;
    wire id_owner1_o;
    wire [32-1:0] id_data1_i;
    wire [5-1:0] id_rs2_o;
    wire id_owner2_o;
    wire [32-1:0] id_data2_i;
    wire [5-1:0] id_rs3_o;
    wire id_owner3_o;
    wire [32-1:0] id_data3_i;
    reg wb0_valid_i=0;
    reg [5-1:0] wb0_rd_i=0;
    reg [32-1:0] wb0_data_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] wb0_tag_i=0;
    reg wb1_valid_i=0;
    reg [5-1:0] wb1_rd_i=0;
    reg [32-1:0] wb1_data_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] wb1_tag_i=0;
    wire [5-1:0] fp_read0_addr_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read0_data_i;
    wire [5-1:0] fp_read1_addr_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read1_data_i;
    wire [5-1:0] fp_read2_addr_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_read2_data_i;
    reg fp_wb_valid_i=0;
    reg [5-1:0] fp_wb_rd_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_wb_data_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_wb_tag_i=0;
    wire [(ISSUE_WIDTH == 2 || FPU_FORMAT == "FD" ? 5 : 4)-1:0] allocate_credit_i;
    reg allocate_ready_i=0;
    wire allocate_valid_o;
    wire [2-1:0] allocate_count_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] allocate0_tag_o;
    wire [32-1:0] allocate0_pc_o;
    wire [32-1:0] allocate0_instr_o;
    wire [5-1:0] allocate0_rd_o;
    wire [2-1:0] allocate0_dest_o;
    wire [32-1:0] allocate0_csr_src_o;
    wire allocate0_store_o;
    wire allocate0_divide_o;
    wire allocate0_double_beat_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] allocate1_tag_o;
    wire [32-1:0] allocate1_pc_o;
    wire [32-1:0] allocate1_instr_o;
    wire [5-1:0] allocate1_rd_o;
    wire [2-1:0] allocate1_dest_o;
    wire [32-1:0] allocate1_csr_src_o;
    wire allocate1_store_o;
    wire allocate1_divide_o;
    wire allocate1_double_beat_o;
    wire source0_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source0_tag_o;
    wire source0_domain_o;
    wire source0_ready_i;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source0_data_i;
    wire source1_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source1_tag_o;
    wire source1_domain_o;
    wire source1_ready_i;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source1_data_i;
    wire source2_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source2_tag_o;
    wire source2_domain_o;
    wire source2_ready_i;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source2_data_i;
    wire source3_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source3_tag_o;
    wire source3_domain_o;
    wire source3_ready_i;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source3_data_i;
    wire source4_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source4_tag_o;
    wire source4_domain_o;
    wire source4_ready_i;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] source4_data_i;
    reg execute0_ready_i=0;
    wire execute0_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_tag_o;
    wire [32-1:0] execute0_pc_o;
    wire [32-1:0] execute0_instr_o;
    wire [32-1:0] execute0_src1_o;
    wire [32-1:0] execute0_src2_o;
    wire [32-1:0] execute0_imm_o;
    wire execute0_late_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source1_tag_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source2_tag_o;
    wire execute0_source1_wait_o;
    wire execute0_source2_wait_o;
    wire execute0_predict_taken_o;
    wire [32-1:0] execute0_predict_target_o;
    wire execute0_predict_token_o;
    wire [3-1:0] execute0_predict_provider_o;
    wire execute0_predict_alternate_o;
    wire [9-1:0] execute0_predict_index0_o;
    wire [9-1:0] execute0_predict_index1_o;
    wire [9-1:0] execute0_predict_index2_o;
    wire [9-1:0] execute0_predict_index3_o;
    wire [10-1:0] execute0_predict_tag0_o;
    wire [10-1:0] execute0_predict_tag1_o;
    wire [10-1:0] execute0_predict_tag2_o;
    wire [10-1:0] execute0_predict_tag3_o;
    wire [12-1:0] execute0_predict_base_index_o;
    wire [12-1:0] execute0_predict_fast_index_o;
    wire [(128*ISSUE_WIDTH)-1:0] execute0_ras_data_o;
    wire [(ISSUE_WIDTH+1)-1:0] execute0_ras_ptr_o;
    wire [(ISSUE_WIDTH+2)-1:0] execute0_ras_count_o;
    reg execute1_ready_i=0;
    wire execute1_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_tag_o;
    wire [32-1:0] execute1_pc_o;
    wire [32-1:0] execute1_instr_o;
    wire [32-1:0] execute1_src1_o;
    wire [32-1:0] execute1_src2_o;
    wire [32-1:0] execute1_imm_o;
    wire execute1_late_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source1_tag_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source2_tag_o;
    wire execute1_source1_wait_o;
    wire execute1_source2_wait_o;
    wire execute1_predict_taken_o;
    wire [32-1:0] execute1_predict_target_o;
    wire execute1_predict_token_o;
    wire [3-1:0] execute1_predict_provider_o;
    wire execute1_predict_alternate_o;
    wire [9-1:0] execute1_predict_index0_o;
    wire [9-1:0] execute1_predict_index1_o;
    wire [9-1:0] execute1_predict_index2_o;
    wire [9-1:0] execute1_predict_index3_o;
    wire [10-1:0] execute1_predict_tag0_o;
    wire [10-1:0] execute1_predict_tag1_o;
    wire [10-1:0] execute1_predict_tag2_o;
    wire [10-1:0] execute1_predict_tag3_o;
    wire [12-1:0] execute1_predict_base_index_o;
    wire [12-1:0] execute1_predict_fast_index_o;
    wire [(128*ISSUE_WIDTH)-1:0] execute1_ras_data_o;
    wire [(ISSUE_WIDTH+1)-1:0] execute1_ras_ptr_o;
    wire [(ISSUE_WIDTH+2)-1:0] execute1_ras_count_o;
    reg mul_req_ready_i=0;
    wire mul_req_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_req_tag_o;
    wire [32-1:0] mul_req_instr_o;
    wire [32-1:0] mul_req_src1_o;
    wire [32-1:0] mul_req_src2_o;
    reg div_req_ready_i=0;
    wire div_req_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_req_tag_o;
    wire [32-1:0] div_req_instr_o;
    wire [32-1:0] div_req_src1_o;
    wire [32-1:0] div_req_src2_o;
    reg lsu_req_ready_i=0;
    wire lsu_req_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_req_tag_o;
    wire [32-1:0] lsu_req_instr_o;
    wire [32-1:0] lsu_req_addr_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_req_store_data_o;
    wire lsu_req_early_o;
    reg csr_req_ready_i=0;
    wire csr_req_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_req_tag_o;
    wire [32-1:0] csr_req_instr_o;
    wire [32-1:0] csr_req_src_o;
    reg fp_req_ready_i=0;
    wire fp_req_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_req_tag_o;
    wire [32-1:0] fp_req_instr_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src1_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src2_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_req_src3_o;
    wire [32-1:0] fp_req_int_src_o;
    wire [3-1:0] fp_req_rm_o;
    wire early_req_valid_o;
    wire [32-1:0] early_req_addr_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] early_req_tag_o;
    reg decode_complete_ready_i=0;
    wire decode_complete_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] decode_complete_tag_o;
    wire decode_complete_exception_o;
    wire [4-1:0] decode_complete_cause_o;
    wire [32-1:0] decode_complete_tval_o;
    wire predict_read0_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] predict_read0_tag_o;
    wire [9-1:0] predict_read0_index0_o;
    wire [9-1:0] predict_read0_index1_o;
    wire [9-1:0] predict_read0_index2_o;
    wire [9-1:0] predict_read0_index3_o;
    wire [10-1:0] predict_read0_tag0_o;
    wire [10-1:0] predict_read0_tag1_o;
    wire [10-1:0] predict_read0_tag2_o;
    wire [10-1:0] predict_read0_tag3_o;
    wire [12-1:0] predict_read0_base_index_o;
    wire predict_read1_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] predict_read1_tag_o;
    wire [9-1:0] predict_read1_index0_o;
    wire [9-1:0] predict_read1_index1_o;
    wire [9-1:0] predict_read1_index2_o;
    wire [9-1:0] predict_read1_index3_o;
    wire [10-1:0] predict_read1_tag0_o;
    wire [10-1:0] predict_read1_tag1_o;
    wire [10-1:0] predict_read1_tag2_o;
    wire [10-1:0] predict_read1_tag3_o;
    wire [12-1:0] predict_read1_base_index_o;
    reg alu0_complete_valid_i=0;
    reg alu0_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu0_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_i=0;
    reg alu1_complete_valid_i=0;
    reg alu1_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu1_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_i=0;
    reg branch_complete_valid_i=0;
    reg branch_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_i=0;
    reg mul_complete_valid_i=0;
    reg mul_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] mul_complete_data_i=0;
    reg div_complete_valid_i=0;
    reg div_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] div_complete_data_i=0;
    reg early_resp_valid_i=0;
    reg [T-1:0] early_resp_tag_i=0;
    reg early_resp_hit_i=0;
    reg [31:0] early_resp_data_i=0;
    reg lsu_complete_valid_i=0;
    reg lsu_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_complete_data_i=0;
    reg csr_complete_valid_i=0;
    reg csr_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] csr_complete_data_i=0;
    reg fp_resp_valid_i=0;
    reg fp_resp_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_resp_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_resp_data_i=0;
    reg [T:0] occupied=0;
    reg [T-1:0] model_head=0;
    reg [1:0] retire=0;
    reg done [0:N-1];
    reg [31:0] xref [0:31];
    reg [B-1:0] fref [0:31];
    assign allocate_credit_i=(T+1)'(N)-occupied;
    assign age_head_i=model_head;
    always #5 clk_i=~clk_i;
    always @(posedge clk_i or negedge rst_n_i) begin
        if(!rst_n_i)begin occupied<=0;model_head<=0;end
        else begin
            model_head<=model_head+T'(retire);
            if(cancel_valid_i) occupied<=(T+1)'(T'(cancel_tag_i-model_head))-(T+1)'(retire);
            else occupied<=occupied+(allocate_valid_o&&allocate_ready_i ?
                (T+1)'(allocate_count_o):0)-(T+1)'(retire);
        end
    end
    always @(posedge clk_i)begin
        if(wb0_valid_i && wb0_rd_i!=0)xref[wb0_rd_i]<=wb0_data_i;
        if(wb1_valid_i && wb1_rd_i!=0 && ISSUE_WIDTH==2)xref[wb1_rd_i]<=wb1_data_i;
        if(fp_wb_valid_i)fref[fp_wb_rd_i]<=fp_wb_data_i;
    end
    assign id_data0_i=(id_rs0_o==0)?0:
        (ISSUE_WIDTH==2 && wb1_valid_i && wb1_rd_i==id_rs0_o)?wb1_data_i:
        (wb0_valid_i && wb0_rd_i==id_rs0_o)?wb0_data_i:xref[id_rs0_o];
    assign id_data1_i=(id_rs1_o==0)?0:
        (ISSUE_WIDTH==2 && wb1_valid_i && wb1_rd_i==id_rs1_o)?wb1_data_i:
        (wb0_valid_i && wb0_rd_i==id_rs1_o)?wb0_data_i:xref[id_rs1_o];
    assign id_data2_i=(id_rs2_o==0)?0:
        (ISSUE_WIDTH==2 && wb1_valid_i && wb1_rd_i==id_rs2_o)?wb1_data_i:
        (wb0_valid_i && wb0_rd_i==id_rs2_o)?wb0_data_i:xref[id_rs2_o];
    assign id_data3_i=(id_rs3_o==0)?0:
        (ISSUE_WIDTH==2 && wb1_valid_i && wb1_rd_i==id_rs3_o)?wb1_data_i:
        (wb0_valid_i && wb0_rd_i==id_rs3_o)?wb0_data_i:xref[id_rs3_o];
    assign fp_read0_data_i=(fp_wb_valid_i && fp_wb_rd_i==fp_read0_addr_o)?
        fp_wb_data_i:fref[fp_read0_addr_o];
    assign fp_read1_data_i=(fp_wb_valid_i && fp_wb_rd_i==fp_read1_addr_o)?
        fp_wb_data_i:fref[fp_read1_addr_o];
    assign fp_read2_data_i=(fp_wb_valid_i && fp_wb_rd_i==fp_read2_addr_o)?
        fp_wb_data_i:fref[fp_read2_addr_o];
    assign source0_ready_i=source0_valid_o && done[source0_tag_o];
    assign source0_data_i=B'(100)+B'(source0_tag_o);
    assign source1_ready_i=source1_valid_o && done[source1_tag_o];
    assign source1_data_i=B'(100)+B'(source1_tag_o);
    assign source2_ready_i=source2_valid_o && done[source2_tag_o];
    assign source2_data_i=B'(100)+B'(source2_tag_o);
    assign source3_ready_i=source3_valid_o && done[source3_tag_o];
    assign source3_data_i=B'(100)+B'(source3_tag_o);
    assign source4_ready_i=source4_valid_o && done[source4_tag_o];
    assign source4_data_i=B'(100)+B'(source4_tag_o);
    reg lsu_complete_device_i=0;
    edrv32_cpu2_issue #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) dut (
        .alu0_complete_valid_i(alu0_complete_valid_i),
        .alu0_complete_ready_i(alu0_complete_ready_i),
        .alu0_complete_tag_i(alu0_complete_tag_i),
        .alu0_complete_data_i(alu0_complete_data_i),
        .alu1_complete_valid_i(alu1_complete_valid_i),
        .alu1_complete_ready_i(alu1_complete_ready_i),
        .alu1_complete_tag_i(alu1_complete_tag_i),
        .alu1_complete_data_i(alu1_complete_data_i),
        .branch_complete_valid_i(branch_complete_valid_i),
        .branch_complete_ready_i(branch_complete_ready_i),
        .branch_complete_tag_i(branch_complete_tag_i),
        .branch_complete_data_i(branch_complete_data_i),
        .mul_complete_valid_i(mul_complete_valid_i),
        .mul_complete_ready_i(mul_complete_ready_i),
        .mul_complete_tag_i(mul_complete_tag_i),
        .mul_complete_data_i(mul_complete_data_i),
        .div_complete_valid_i(div_complete_valid_i),
        .div_complete_ready_i(div_complete_ready_i),
        .div_complete_tag_i(div_complete_tag_i),
        .div_complete_data_i(div_complete_data_i),
        .early_resp_valid_i(early_resp_valid_i),
        .early_resp_tag_i(early_resp_tag_i),
        .early_resp_hit_i(early_resp_hit_i),
        .early_resp_data_i(early_resp_data_i),
        .lsu_complete_valid_i(lsu_complete_valid_i),
        .lsu_complete_ready_i(lsu_complete_ready_i),
        .lsu_complete_tag_i(lsu_complete_tag_i),
        .lsu_complete_data_i(lsu_complete_data_i),
        .csr_complete_valid_i(csr_complete_valid_i),
        .csr_complete_ready_i(csr_complete_ready_i),
        .csr_complete_tag_i(csr_complete_tag_i),
        .csr_complete_data_i(csr_complete_data_i),
        .fp_resp_valid_i(fp_resp_valid_i),
        .fp_resp_ready_i(fp_resp_ready_i),
        .fp_resp_tag_i(fp_resp_tag_i),
        .fp_resp_data_i(fp_resp_data_i),
        .lsu_complete_device_i(lsu_complete_device_i),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i),
        .csr_fs_i(csr_fs_i),
        .csr_frm_i(csr_frm_i),
        .ib_head0_valid_i(ib_head0_valid_i),
        .ib_head0_pc_i(ib_head0_pc_i),
        .ib_head0_instr_i(ib_head0_instr_i),
        .ib_head0_error_i(ib_head0_error_i),
        .ib_head0_candidates_i(ib_head0_candidates_i),
        .ib_head0_predict_taken_i(ib_head0_predict_taken_i),
        .ib_head0_predict_target_i(ib_head0_predict_target_i),
        .ib_head0_predict_token_i(ib_head0_predict_token_i),
        .ib_head0_predict_provider_i(ib_head0_predict_provider_i),
        .ib_head0_predict_alternate_i(ib_head0_predict_alternate_i),
        .ib_head0_predict_index0_i(ib_head0_predict_index0_i),
        .ib_head0_predict_index1_i(ib_head0_predict_index1_i),
        .ib_head0_predict_index2_i(ib_head0_predict_index2_i),
        .ib_head0_predict_index3_i(ib_head0_predict_index3_i),
        .ib_head0_predict_tag0_i(ib_head0_predict_tag0_i),
        .ib_head0_predict_tag1_i(ib_head0_predict_tag1_i),
        .ib_head0_predict_tag2_i(ib_head0_predict_tag2_i),
        .ib_head0_predict_tag3_i(ib_head0_predict_tag3_i),
        .ib_head0_predict_base_index_i(ib_head0_predict_base_index_i),
        .ib_head0_predict_fast_index_i(ib_head0_predict_fast_index_i),
        .ib_head0_ras_data_i(ib_head0_ras_data_i),
        .ib_head0_ras_ptr_i(ib_head0_ras_ptr_i),
        .ib_head0_ras_count_i(ib_head0_ras_count_i),
        .ib_head1_valid_i(ib_head1_valid_i),
        .ib_head1_pc_i(ib_head1_pc_i),
        .ib_head1_instr_i(ib_head1_instr_i),
        .ib_head1_error_i(ib_head1_error_i),
        .ib_head1_candidates_i(ib_head1_candidates_i),
        .ib_head1_predict_taken_i(ib_head1_predict_taken_i),
        .ib_head1_predict_target_i(ib_head1_predict_target_i),
        .ib_head1_predict_token_i(ib_head1_predict_token_i),
        .ib_head1_predict_provider_i(ib_head1_predict_provider_i),
        .ib_head1_predict_alternate_i(ib_head1_predict_alternate_i),
        .ib_head1_predict_index0_i(ib_head1_predict_index0_i),
        .ib_head1_predict_index1_i(ib_head1_predict_index1_i),
        .ib_head1_predict_index2_i(ib_head1_predict_index2_i),
        .ib_head1_predict_index3_i(ib_head1_predict_index3_i),
        .ib_head1_predict_tag0_i(ib_head1_predict_tag0_i),
        .ib_head1_predict_tag1_i(ib_head1_predict_tag1_i),
        .ib_head1_predict_tag2_i(ib_head1_predict_tag2_i),
        .ib_head1_predict_tag3_i(ib_head1_predict_tag3_i),
        .ib_head1_predict_base_index_i(ib_head1_predict_base_index_i),
        .ib_head1_predict_fast_index_i(ib_head1_predict_fast_index_i),
        .ib_head1_ras_data_i(ib_head1_ras_data_i),
        .ib_head1_ras_ptr_i(ib_head1_ras_ptr_i),
        .ib_head1_ras_count_i(ib_head1_ras_count_i),
        .ib_remove_count_o(ib_remove_count_o),
        .id_rs0_o(id_rs0_o),
        .id_owner0_o(id_owner0_o),
        .id_data0_i(id_data0_i),
        .id_rs1_o(id_rs1_o),
        .id_owner1_o(id_owner1_o),
        .id_data1_i(id_data1_i),
        .id_rs2_o(id_rs2_o),
        .id_owner2_o(id_owner2_o),
        .id_data2_i(id_data2_i),
        .id_rs3_o(id_rs3_o),
        .id_owner3_o(id_owner3_o),
        .id_data3_i(id_data3_i),
        .wb0_valid_i(wb0_valid_i),
        .wb0_rd_i(wb0_rd_i),
        .wb0_data_i(wb0_data_i),
        .wb0_tag_i(wb0_tag_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_rd_i(wb1_rd_i),
        .wb1_data_i(wb1_data_i),
        .wb1_tag_i(wb1_tag_i),
        .fp_read0_addr_o(fp_read0_addr_o),
        .fp_read0_data_i(fp_read0_data_i),
        .fp_read1_addr_o(fp_read1_addr_o),
        .fp_read1_data_i(fp_read1_data_i),
        .fp_read2_addr_o(fp_read2_addr_o),
        .fp_read2_data_i(fp_read2_data_i),
        .fp_wb_valid_i(fp_wb_valid_i),
        .fp_wb_rd_i(fp_wb_rd_i),
        .fp_wb_data_i(fp_wb_data_i),
        .fp_wb_tag_i(fp_wb_tag_i),
        .allocate_credit_i(allocate_credit_i),
        .allocate_ready_i(allocate_ready_i),
        .allocate_valid_o(allocate_valid_o),
        .allocate_count_o(allocate_count_o),
        .allocate0_tag_o(allocate0_tag_o),
        .allocate0_pc_o(allocate0_pc_o),
        .allocate0_instr_o(allocate0_instr_o),
        .allocate0_rd_o(allocate0_rd_o),
        .allocate0_dest_o(allocate0_dest_o),
        .allocate0_csr_src_o(allocate0_csr_src_o),
        .allocate0_store_o(allocate0_store_o),
        .allocate0_divide_o(allocate0_divide_o),
        .allocate0_double_beat_o(allocate0_double_beat_o),
        .allocate1_tag_o(allocate1_tag_o),
        .allocate1_pc_o(allocate1_pc_o),
        .allocate1_instr_o(allocate1_instr_o),
        .allocate1_rd_o(allocate1_rd_o),
        .allocate1_dest_o(allocate1_dest_o),
        .allocate1_csr_src_o(allocate1_csr_src_o),
        .allocate1_store_o(allocate1_store_o),
        .allocate1_divide_o(allocate1_divide_o),
        .allocate1_double_beat_o(allocate1_double_beat_o),
        .source0_valid_o(source0_valid_o),
        .source0_tag_o(source0_tag_o),
        .source0_domain_o(source0_domain_o),
        .source0_ready_i(source0_ready_i),
        .source0_data_i(source0_data_i),
        .source1_valid_o(source1_valid_o),
        .source1_tag_o(source1_tag_o),
        .source1_domain_o(source1_domain_o),
        .source1_ready_i(source1_ready_i),
        .source1_data_i(source1_data_i),
        .source2_valid_o(source2_valid_o),
        .source2_tag_o(source2_tag_o),
        .source2_domain_o(source2_domain_o),
        .source2_ready_i(source2_ready_i),
        .source2_data_i(source2_data_i),
        .source3_valid_o(source3_valid_o),
        .source3_tag_o(source3_tag_o),
        .source3_domain_o(source3_domain_o),
        .source3_ready_i(source3_ready_i),
        .source3_data_i(source3_data_i),
        .source4_valid_o(source4_valid_o),
        .source4_tag_o(source4_tag_o),
        .source4_domain_o(source4_domain_o),
        .source4_ready_i(source4_ready_i),
        .source4_data_i(source4_data_i),
        .execute0_ready_i(execute0_ready_i),
        .execute0_valid_o(execute0_valid_o),
        .execute0_tag_o(execute0_tag_o),
        .execute0_pc_o(execute0_pc_o),
        .execute0_instr_o(execute0_instr_o),
        .execute0_src1_o(execute0_src1_o),
        .execute0_src2_o(execute0_src2_o),
        .execute0_imm_o(execute0_imm_o),
        .execute0_late_o(execute0_late_o),
        .execute0_source1_tag_o(execute0_source1_tag_o),
        .execute0_source2_tag_o(execute0_source2_tag_o),
        .execute0_source1_wait_o(execute0_source1_wait_o),
        .execute0_source2_wait_o(execute0_source2_wait_o),
        .execute0_predict_taken_o(execute0_predict_taken_o),
        .execute0_predict_target_o(execute0_predict_target_o),
        .execute0_predict_token_o(execute0_predict_token_o),
        .execute0_predict_provider_o(execute0_predict_provider_o),
        .execute0_predict_alternate_o(execute0_predict_alternate_o),
        .execute0_predict_index0_o(execute0_predict_index0_o),
        .execute0_predict_index1_o(execute0_predict_index1_o),
        .execute0_predict_index2_o(execute0_predict_index2_o),
        .execute0_predict_index3_o(execute0_predict_index3_o),
        .execute0_predict_tag0_o(execute0_predict_tag0_o),
        .execute0_predict_tag1_o(execute0_predict_tag1_o),
        .execute0_predict_tag2_o(execute0_predict_tag2_o),
        .execute0_predict_tag3_o(execute0_predict_tag3_o),
        .execute0_predict_base_index_o(execute0_predict_base_index_o),
        .execute0_predict_fast_index_o(execute0_predict_fast_index_o),
        .execute0_ras_data_o(execute0_ras_data_o),
        .execute0_ras_ptr_o(execute0_ras_ptr_o),
        .execute0_ras_count_o(execute0_ras_count_o),
        .execute1_ready_i(execute1_ready_i),
        .execute1_valid_o(execute1_valid_o),
        .execute1_tag_o(execute1_tag_o),
        .execute1_pc_o(execute1_pc_o),
        .execute1_instr_o(execute1_instr_o),
        .execute1_src1_o(execute1_src1_o),
        .execute1_src2_o(execute1_src2_o),
        .execute1_imm_o(execute1_imm_o),
        .execute1_late_o(execute1_late_o),
        .execute1_source1_tag_o(execute1_source1_tag_o),
        .execute1_source2_tag_o(execute1_source2_tag_o),
        .execute1_source1_wait_o(execute1_source1_wait_o),
        .execute1_source2_wait_o(execute1_source2_wait_o),
        .execute1_predict_taken_o(execute1_predict_taken_o),
        .execute1_predict_target_o(execute1_predict_target_o),
        .execute1_predict_token_o(execute1_predict_token_o),
        .execute1_predict_provider_o(execute1_predict_provider_o),
        .execute1_predict_alternate_o(execute1_predict_alternate_o),
        .execute1_predict_index0_o(execute1_predict_index0_o),
        .execute1_predict_index1_o(execute1_predict_index1_o),
        .execute1_predict_index2_o(execute1_predict_index2_o),
        .execute1_predict_index3_o(execute1_predict_index3_o),
        .execute1_predict_tag0_o(execute1_predict_tag0_o),
        .execute1_predict_tag1_o(execute1_predict_tag1_o),
        .execute1_predict_tag2_o(execute1_predict_tag2_o),
        .execute1_predict_tag3_o(execute1_predict_tag3_o),
        .execute1_predict_base_index_o(execute1_predict_base_index_o),
        .execute1_predict_fast_index_o(execute1_predict_fast_index_o),
        .execute1_ras_data_o(execute1_ras_data_o),
        .execute1_ras_ptr_o(execute1_ras_ptr_o),
        .execute1_ras_count_o(execute1_ras_count_o),
        .mul_req_ready_i(mul_req_ready_i),
        .mul_req_valid_o(mul_req_valid_o),
        .mul_req_tag_o(mul_req_tag_o),
        .mul_req_instr_o(mul_req_instr_o),
        .mul_req_src1_o(mul_req_src1_o),
        .mul_req_src2_o(mul_req_src2_o),
        .div_req_ready_i(div_req_ready_i),
        .div_req_valid_o(div_req_valid_o),
        .div_req_tag_o(div_req_tag_o),
        .div_req_instr_o(div_req_instr_o),
        .div_req_src1_o(div_req_src1_o),
        .div_req_src2_o(div_req_src2_o),
        .lsu_req_ready_i(lsu_req_ready_i),
        .lsu_req_valid_o(lsu_req_valid_o),
        .lsu_req_tag_o(lsu_req_tag_o),
        .lsu_req_instr_o(lsu_req_instr_o),
        .lsu_req_addr_o(lsu_req_addr_o),
        .lsu_req_store_data_o(lsu_req_store_data_o),
        .lsu_req_early_o(lsu_req_early_o),
        .csr_req_ready_i(csr_req_ready_i),
        .csr_req_valid_o(csr_req_valid_o),
        .csr_req_tag_o(csr_req_tag_o),
        .csr_req_instr_o(csr_req_instr_o),
        .csr_req_src_o(csr_req_src_o),
        .fp_req_ready_i(fp_req_ready_i),
        .fp_req_valid_o(fp_req_valid_o),
        .fp_req_tag_o(fp_req_tag_o),
        .fp_req_instr_o(fp_req_instr_o),
        .fp_req_src1_o(fp_req_src1_o),
        .fp_req_src2_o(fp_req_src2_o),
        .fp_req_src3_o(fp_req_src3_o),
        .fp_req_int_src_o(fp_req_int_src_o),
        .fp_req_rm_o(fp_req_rm_o),
        .early_req_valid_o(early_req_valid_o),
        .early_req_addr_o(early_req_addr_o),
        .early_req_tag_o(early_req_tag_o),
        .decode_complete_ready_i(decode_complete_ready_i),
        .decode_complete_valid_o(decode_complete_valid_o),
        .decode_complete_tag_o(decode_complete_tag_o),
        .decode_complete_exception_o(decode_complete_exception_o),
        .decode_complete_cause_o(decode_complete_cause_o),
        .decode_complete_tval_o(decode_complete_tval_o),
        .predict_read0_valid_o(predict_read0_valid_o),
        .predict_read0_tag_o(predict_read0_tag_o),
        .predict_read0_index0_o(predict_read0_index0_o),
        .predict_read0_index1_o(predict_read0_index1_o),
        .predict_read0_index2_o(predict_read0_index2_o),
        .predict_read0_index3_o(predict_read0_index3_o),
        .predict_read0_tag0_o(predict_read0_tag0_o),
        .predict_read0_tag1_o(predict_read0_tag1_o),
        .predict_read0_tag2_o(predict_read0_tag2_o),
        .predict_read0_tag3_o(predict_read0_tag3_o),
        .predict_read0_base_index_o(predict_read0_base_index_o),
        .predict_read1_valid_o(predict_read1_valid_o),
        .predict_read1_tag_o(predict_read1_tag_o),
        .predict_read1_index0_o(predict_read1_index0_o),
        .predict_read1_index1_o(predict_read1_index1_o),
        .predict_read1_index2_o(predict_read1_index2_o),
        .predict_read1_index3_o(predict_read1_index3_o),
        .predict_read1_tag0_o(predict_read1_tag0_o),
        .predict_read1_tag1_o(predict_read1_tag1_o),
        .predict_read1_tag2_o(predict_read1_tag2_o),
        .predict_read1_tag3_o(predict_read1_tag3_o),
        .predict_read1_base_index_o(predict_read1_base_index_o),
        // I06 observation-only outputs.
        .issue_hpm_o(),
        .issue_pair_cause_o(),
        .issue_wait_o()
    );
    reg csr_seen=0;
    reg [T-1:0] csr_seen_tag;
    always @(posedge clk_i or negedge rst_n_i) begin
        if(!rst_n_i)csr_seen<=0;
        else if(csr_req_valid_o && csr_req_ready_i)csr_seen<=1;
    end
    always @(posedge clk_i)if(csr_req_valid_o && csr_req_ready_i)csr_seen_tag<=csr_req_tag_o;
    task tick; @(posedge clk_i); #1; endtask
    task clear;
        @(negedge clk_i);rst_n_i=0;ib_head0_valid_i=0;ib_head1_valid_i=0;
        cancel_valid_i=0;retire=0;fp_wb_valid_i=0;
        early_resp_valid_i=0;early_resp_hit_i=0;
        for(integer t=0;t<N;t++)done[t]=0;
        tick();rst_n_i=1;tick();
    endtask
    function [31:0] instruction(input integer kind,input integer rd,input integer a,input integer b);
        case(kind)
            0:instruction=32'h33;
            1:instruction=32'h63;
            2:instruction=32'h67;
            3:instruction=32'h2003;
            4:instruction=32'h02000033;
            5:instruction=32'h02004033;
            6:instruction=32'h53;
            7:instruction=32'hb0002073;
            default:instruction=0;
        endcase
        instruction=instruction|(32'(rd)<<7)|(32'(a)<<15)|(32'(b)<<20);
        if(kind==7)instruction=32'hb0002073|(32'(rd)<<7)|(32'(a)<<15);
    endfunction
    function bit pipe1(input integer kind);pipe1=kind<=2 || kind==4;endfunction
    function bit pairs(input integer old,input integer young,input bit raw);
        bit supported;
        supported=(pipe1(old)||pipe1(young)) && old!=7 && young!=7 &&
            !(old==young && old!=0) && !((old==1||old==2)&&(young==1||young==2)) &&
            (old!=6||young==0) && (young!=6||old==0);
        if(raw)supported=supported && (old==0||old==3) && (young==0||young==1);
        pairs=ISSUE_WIDTH==2 && supported;
    endfunction
    task route(input integer kind,input integer pipe,input integer expected_tag);
        bit observed;
        case(kind)
            0,1,2: observed=(pipe==0)?execute0_valid_o&&execute0_tag_o==T'(expected_tag):
                execute1_valid_o&&execute1_tag_o==T'(expected_tag);
            3:observed=lsu_req_valid_o&&lsu_req_tag_o==T'(expected_tag);
            4:observed=mul_req_valid_o&&mul_req_tag_o==T'(expected_tag);
            5:observed=div_req_valid_o&&div_req_tag_o==T'(expected_tag);
            6:observed=fp_req_valid_o&&fp_req_tag_o==T'(expected_tag);
            7:observed=(csr_req_valid_o&&csr_req_tag_o==T'(expected_tag)) ||
                (csr_seen&&csr_seen_tag==T'(expected_tag));
            default:observed=0;
        endcase
        if(!observed)$fatal(1,"route kind%0d pipe%0d tag%0d at%0t",kind,pipe,expected_tag,$time);
    endtask
    integer r0,r1,a0,a1,b0,b1;
    bit raw,expected_pair;
    integer old_pipe,young_pipe;
    integer cases=0;
    integer cycle_count=0;
    integer producer_cycle;
    always @(posedge clk_i)cycle_count<=cycle_count+1;
    initial begin
        allocate_ready_i=1;execute0_ready_i=1;execute1_ready_i=1;
        mul_req_ready_i=1;div_req_ready_i=1;lsu_req_ready_i=1;
        csr_req_ready_i=1;fp_req_ready_i=1;decode_complete_ready_i=1;
        csr_fs_i=3;csr_frm_i=0;ib_head0_pc_i=32'h100;ib_head1_pc_i=32'h104;
        for(integer r=0;r<32;r++)begin xref[r]=32'(r*7);fref[r]=B'(r*11);end
        clear();
        for(integer r=1;r<32;r++)begin
            @(negedge clk_i);wb0_valid_i=1;wb0_rd_i=5'(r);wb0_data_i=32'(r*7);tick();
        end
        wb0_valid_i=0;
        // Full type matrix and dependency relations in both program orders.
        for(integer old=0;old<8;old++)begin
            for(integer young=0;young<8;young++)begin
                if(FPU_FORMAT!="NONE" || (old!=6 && young!=6))begin
                    for(integer relation=0;relation<7;relation++)begin
                        clear();r0=6;r1=7;a0=2;b0=3;a1=4;b1=5;
                        case(relation)
                            1:a1=r0;
                            2:r1=r0;
                            3:begin a0=6;r1=6;r0=8;end
                            4:begin r0=0;a1=0;end
                            5:b1=r0;
                            6:begin a1=r0;b1=r0;end
                            default:begin end
                        endcase
                        raw=(old!=1) && (old==6 || r0!=0) && ((r0==a1) || ((young==0 || young==1 || young==4 ||
                            young==5 || young==6) && (r0==b1))) &&
                            ((old==6)==(young==6));
                        expected_pair=pairs(old,young,raw);
                        @(negedge clk_i);ib_head0_valid_i=1;ib_head1_valid_i=1;
                        ib_head0_instr_i=instruction(old,r0,a0,b0);
                        ib_head1_instr_i=instruction(young,r1,a1,b1);
                        #1;
                        if(!allocate_valid_o || allocate_count_o!==(expected_pair?2:1) ||
                            ib_remove_count_o!==(expected_pair?2:1))
                            $fatal(1,"pair %0d/%0d relation%0d expected%0d got%0d valid%b at%0t",
                                old,young,relation,expected_pair?2:1,allocate_count_o,
                                allocate_valid_o,$time);
                        if(allocate0_tag_o!==0 || (expected_pair && allocate1_tag_o!==1))
                            $fatal(1,"program tag order");
                        old_pipe=expected_pair&&!pipe1(young)?1:0;
                        young_pipe=1-old_pipe;
                        tick();ib_head0_valid_i=0;ib_head1_valid_i=0;#1;
                        route(old,old_pipe,0);
                        if(expected_pair)begin
                            route(young,young_pipe,1);
                            if(raw && !(young_pipe==0?execute0_late_o:execute1_late_o))
                                $fatal(1,"same-group RAW did not choose MEM");
                        end
                        cases++;
                    end
                end
            end
        end
        // A young synchronous exception keeps the older program-slot allocation intact.
        clear();@(negedge clk_i);ib_head0_valid_i=1;ib_head1_valid_i=1;
        ib_head0_instr_i=instruction(0,6,2,3);ib_head1_instr_i=32'hffffffff;
        #1;if(allocate_count_o!==(ISSUE_WIDTH==2?2:1))$fatal(1,"young exception prefix");
        tick();ib_head0_valid_i=0;ib_head1_valid_i=0;#1;route(0,0,0);
        if(ISSUE_WIDTH==2 && (!decode_complete_valid_o || decode_complete_tag_o!==1 ||
            decode_complete_cause_o!==2 || decode_complete_tval_o!==32'hffffffff))
            $fatal(1,"young decode exception tag/payload");
        // CV04: mock LSU hit returns at EX distance 1; ordinary load returns at distance 2.
        for(integer ordinary=0;ordinary<2;ordinary++)begin
            clear();@(negedge clk_i);ib_head0_valid_i=1;
            if(ordinary!=0)begin
                ib_head0_instr_i=32'h06400213; // ADDI x4,x0,100.
                tick();ib_head0_instr_i=instruction(3,6,4,0);
                alu0_complete_valid_i=1;alu0_complete_ready_i=1;alu0_complete_tag_i=0;
                alu0_complete_data_i=B'(100);
            end else ib_head0_instr_i=instruction(3,6,4,0);
            #1;if(early_req_valid_o!==(ordinary==0))$fatal(1,"short/ordinary qualification");
            tick();producer_cycle=cycle_count;
            alu0_complete_valid_i=0;if(ordinary!=0)done[0]=1;
            ib_head0_instr_i=instruction(0,7,6,3)|32'h1000;#1;
            if(ISSUE_WIDTH==1 && ordinary==0) begin
                if(!allocate_valid_o)$fatal(1,"short consumer did not reserve local entry");
                execute0_ready_i=0;
                tick();ib_head0_valid_i=0;
                #1;if(execute0_valid_o)$fatal(1,"short consumer executed without captured hit");
                early_resp_valid_i=1;early_resp_tag_i=0;
                early_resp_hit_i=1;early_resp_data_i=5;#1;
                if(!execute0_valid_o || execute0_src1_o!=5 || execute0_late_o ||
                    cycle_count-producer_cycle!=1)$fatal(1,"registered short-load EX interval");
                tick();early_resp_valid_i=0;early_resp_hit_i=0;
                repeat(2)begin tick();if(!execute0_valid_o || execute0_src1_o!=5)
                    $fatal(1,"short source not retained under EX backpressure");end
                execute0_ready_i=1;tick();
            end else begin
            if(allocate_valid_o)$fatal(1,"load source available before its specified return");
            if(ordinary!=0)begin
                tick();if(allocate_valid_o)$fatal(1,"ordinary load returned at distance 1");
            end
            @(negedge clk_i);lsu_complete_valid_i=1;lsu_complete_ready_i=1;
            lsu_complete_tag_i=T'(ordinary);lsu_complete_data_i=B'(5);#1;
            if(!allocate_valid_o)$fatal(1,"load result not captured at its return edge");
            tick();ib_head0_valid_i=0;lsu_complete_valid_i=0;#1;
            if(cycle_count-producer_cycle!==ordinary+1 || execute0_src1_o!==5 || execute0_late_o)
                $fatal(1,"load distance expected%0d got%0d",ordinary+1,cycle_count-producer_cycle);
            end
        end
        if(ISSUE_WIDTH==1) begin
            clear();@(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=instruction(3,6,4,0);tick();
            ib_head0_instr_i=instruction(0,7,6,3);#1;
            if(!allocate_valid_o)$fatal(1,"failed-short consumer local allocation");
            tick();ib_head0_valid_i=0;early_resp_valid_i=1;early_resp_tag_i=0;
            early_resp_hit_i=0;#1;
            if(execute0_valid_o)$fatal(1,"failed early result used");
            tick();early_resp_valid_i=0;
            lsu_complete_valid_i=1;lsu_complete_ready_i=1;
            lsu_complete_tag_i=0;lsu_complete_data_i=9;
            tick();lsu_complete_valid_i=0;#1;
            if(!execute0_valid_o || execute0_src1_o!=9)
                $fatal(1,"failed short load did not capture ordinary completion");
            tick();
        end
        // An early query whose ordinary request misses the next edge expires, without reallocation.
        clear();lsu_req_ready_i=0;@(negedge clk_i);ib_head0_valid_i=1;
        ib_head0_instr_i=instruction(3,6,4,0);#1;
        if(!early_req_valid_o || early_req_tag_o!==0)$fatal(1,"early query allocation tag");
        tick();ib_head0_valid_i=0;#1;
        if(!lsu_req_valid_o || lsu_req_early_o)$fatal(1,"blocked request advertised early reuse");
        tick();lsu_req_ready_i=1;#1;
        if(!lsu_req_valid_o || lsu_req_early_o || early_req_valid_o ||
            allocate_credit_i!==(T+1)'(N-1) || ib_remove_count_o!==0)
            $fatal(1,"expired early query reused or load reallocated");
        tick();if(lsu_req_valid_o)$fatal(1,"load request duplicated");
        // Latest writer wins; a suffix cancel restores the surviving producer version.
        clear();@(negedge clk_i);ib_head0_valid_i=1;
        ib_head0_instr_i=instruction(0,6,2,3);tick();
        ib_head0_instr_i=instruction(0,6,2,3);tick();ib_head0_valid_i=0;
        @(negedge clk_i);ib_head0_instr_i=instruction(0,7,6,3);ib_head0_valid_i=1;
        #1;if(!source0_valid_o || source0_tag_o!==1)$fatal(1,"latest WAW tag");
        cancel_valid_i=1;cancel_tag_i=1;tick();cancel_valid_i=0;#1;
        if(!source0_valid_o || source0_tag_o!==0)$fatal(1,"cancel restore");
        done[0]=1;#1;if(!allocate_valid_o)$fatal(1,"completed source not available");
        tick();ib_head0_valid_i=0;#1;
        if(execute0_src1_o!==100)$fatal(1,"local source capture");
        // Accepted completion and source capture on the same edge must not lose the value.
        clear();@(negedge clk_i);ib_head0_valid_i=1;
        ib_head0_instr_i=instruction(0,6,2,3);tick();
        ib_head0_instr_i=instruction(0,7,6,3)|32'h1000;#1;
        if(allocate_valid_o)$fatal(1,"shift issued with an unavailable source");
        alu0_complete_valid_i=1;alu0_complete_ready_i=1;alu0_complete_tag_i=0;
        alu0_complete_data_i=B'(32'h123);#1;
        if(!allocate_valid_o)$fatal(1,"accepted result unavailable at capture edge");
        tick();ib_head0_valid_i=0;alu0_complete_valid_i=0;#1;
        if(!execute0_valid_o || execute0_late_o || execute0_src1_o!==32'h123)
            $fatal(1,"same-edge result lost between ID/EX and completion bank");
        // BE1: a bank-blocked ALU result still forwards to the next load address.
        for(int pipe=0;pipe<ISSUE_WIDTH;pipe++)begin
            clear();@(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=instruction(0,6,2,3);tick();
            ib_head0_instr_i=instruction(3,7,6,0);#1;
            if(allocate_valid_o)$fatal(1,"load used unavailable ALU address");
            alu0_complete_valid_i=(pipe==0);alu1_complete_valid_i=(pipe==1);
            alu0_complete_ready_i=0;alu1_complete_ready_i=0;
            alu0_complete_tag_i=0;alu1_complete_tag_i=0;
            alu0_complete_data_i=B'(32'h10000400);alu1_complete_data_i=B'(32'h10000400);
            #1;if(!allocate_valid_o || early_req_valid_o)
                $fatal(1,"bank-blocked result did not feed ordinary load");
            tick();ib_head0_valid_i=0;alu0_complete_valid_i=0;alu1_complete_valid_i=0;#1;
            if(!lsu_req_valid_o || lsu_req_addr_o!=32'h10000400)
                $fatal(1,"blocked ALU address lost at source capture");
            @(negedge clk_i);cancel_valid_i=1;cancel_tag_i=0;tick();
            cancel_valid_i=0;tick();
            @(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=instruction(0,6,2,3);tick();
            ib_head0_instr_i=instruction(3,7,6,0);#1;
            if(allocate_valid_o)$fatal(1,"canceled skid value leaked into reused tag");
            alu0_complete_valid_i=1;alu0_complete_tag_i=0;
            alu0_complete_data_i=B'(32'h10000800);#1;
            if(!allocate_valid_o)$fatal(1,"reused tag did not accept new result");
            tick();ib_head0_valid_i=0;alu0_complete_valid_i=0;#1;
            if(!lsu_req_valid_o || lsu_req_addr_o!=32'h10000800)
                $fatal(1,"old skid value survived tag reuse");
        end
        // An uncommitted but completed rs1 still disqualifies early AGU.
        clear();@(negedge clk_i);ib_head0_valid_i=1;
        ib_head0_instr_i=instruction(0,6,2,3);tick();
        done[0]=1;ib_head0_instr_i=instruction(3,7,6,0);#1;
        if(!allocate_valid_o || early_req_valid_o)$fatal(1,"early pending producer exclusion");
        tick();ib_head0_valid_i=0;
        if(lsu_req_early_o)$fatal(1,"ordinary load marked early");
        // A device preparation cannot bypass to ID; the real data arrives at tagged WB.
        clear();@(negedge clk_i);ib_head0_valid_i=1;
        ib_head0_instr_i=instruction(3,6,2,0);tick();
        ib_head0_instr_i=instruction(0,7,6,3)|32'h1000;
        lsu_complete_valid_i=1;lsu_complete_ready_i=1;lsu_complete_tag_i=0;
        lsu_complete_data_i=B'(32'hbad);lsu_complete_device_i=1;#1;
        if(allocate_valid_o !== (ISSUE_WIDTH==1))
            $fatal(1,"device preparation/local short reservation boundary");
        tick();lsu_complete_valid_i=0;lsu_complete_device_i=0;
        if(ISSUE_WIDTH==1)begin
            ib_head0_valid_i=0;#1;
            if(execute0_valid_o)$fatal(1,"device preparation executed as short result");
        end
        @(negedge clk_i);retire=1;tick();retire=0;
        wb0_valid_i=1;wb0_rd_i=6;wb0_tag_i=0;wb0_data_i=32'h123;#1;
        if(ISSUE_WIDTH==2 && !allocate_valid_o)$fatal(1,"device final WB unavailable to ID");
        tick();ib_head0_valid_i=0;wb0_valid_i=0;#1;
        if(execute0_src1_o!==32'h123)$fatal(1,"device final data lost at ID/EX");
        // Local unit backpressure does not freeze another execution class.
        clear();div_req_ready_i=0;
        @(negedge clk_i);ib_head0_valid_i=1;ib_head0_instr_i=instruction(5,6,2,3);tick();
        ib_head0_instr_i=instruction(0,7,2,3);#1;
        if(!allocate_valid_o)$fatal(1,"DIV blocked unrelated ALU");
        tick();ib_head0_valid_i=0;
        if(!div_req_valid_o || !execute0_valid_o)$fatal(1,"local class progress");
        div_req_ready_i=1;
        if(FPU_FORMAT!="NONE")begin
            // f0 is a versioned FP source, independent of the hardwired integer x0.
            clear();@(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=instruction(6,0,2,3);tick();
            ib_head0_instr_i=instruction(6,1,0,3);#1;
            if(allocate_valid_o || !source0_valid_o || !source0_domain_o || source0_tag_o!==0)
                $fatal(1,"FP f0 was treated as integer x0");
            tick();
            fp_resp_valid_i=1;fp_resp_ready_i=1;fp_resp_tag_i=0;
            fp_resp_data_i=B'(64'hffffffff3f800000);#1;
            if(!allocate_valid_o)$fatal(1,"FP accepted-result forwarding unavailable");
            tick();ib_head0_valid_i=0;fp_resp_valid_i=0;#1;
            if(!fp_req_valid_o || fp_req_src1_o!==B'(64'hffffffff3f800000))
                $fatal(1,"FP raw source bits were not captured");
        end
        if(FPU_FORMAT!="NONE")begin
            clear();@(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=instruction(7,6,2,0);tick();
            csr_fs_i=0;ib_head0_instr_i=instruction(6,8,2,3)|32'h7000;#1;
            if(allocate_valid_o)$fatal(1,"FP sampled FS/frm before older CSR retirement");
            @(negedge clk_i);retire=1;tick();retire=0;csr_fs_i=3;csr_frm_i=4;
            fp_req_ready_i=0;#1;
            if(!allocate_valid_o)$fatal(1,"FP did not resume after CSR retirement");
            tick();ib_head0_valid_i=0;csr_frm_i=0;#1;
            if(!fp_req_valid_o || fp_req_rm_o!==4)$fatal(1,"dynamic rm capture");
            tick();if(!fp_req_valid_o || fp_req_rm_o!==4)$fatal(1,"FP request changed under stall");
            fp_req_ready_i=1;
        end
        if(FPU_FORMAT=="FD")begin
            // Two older FP writers share f9; preserve the newest version, including rd==rs3.
            clear();@(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=instruction(6,9,2,3);tick();
            ib_head0_instr_i=instruction(6,9,2,3);tick();ib_head0_valid_i=0;
            @(negedge clk_i);ib_head0_valid_i=1;
            ib_head0_instr_i=(32'd9<<27)|(32'd3<<20)|(32'd2<<15)|(32'd9<<7)|32'h43;
            tick();ib_head0_valid_i=0;
            if(fp_req_valid_o && fp_req_tag_o==2)$fatal(1,"incomplete FMA accepted");
            @(negedge clk_i);retire=1;tick();retire=0;
            fp_wb_valid_i=1;fp_wb_rd_i=9;fp_wb_tag_i=0;
            fp_wb_data_i=B'(64'hdeadbeef12345678);tick();fp_wb_valid_i=0;#1;
            if(fp_req_valid_o)$fatal(1,"rs3 used the older same-register WB version");
            @(negedge clk_i);retire=1;tick();retire=0;
            fp_wb_valid_i=1;fp_wb_rd_i=9;fp_wb_tag_i=1;
            fp_wb_data_i=B'(64'h1122334455667788);tick();fp_wb_valid_i=0;#1;
            if(!fp_req_valid_o || fp_req_tag_o!==2 || fp_req_src3_o!==B'(64'h1122334455667788))
                $fatal(1,"rs3 tagged WB version lost: %h",fp_req_src3_o);
        end
        $display("PASS CV02/CV04/CV05 issue %0d matrix cases WIDTH=%0d FORMAT=%s",
            cases,ISSUE_WIDTH,FPU_FORMAT);$finish;
    end
endmodule
